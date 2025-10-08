/**
 * Search modules handler
 * Supports three search modes:
 * - keyword: FTS5 full-text search only
 * - semantic: Vectorize semantic search only
 * - hybrid: Both FTS5 and Vectorize, merged by relevance (default)
 */

import type { Context } from 'hono';
import type { Env, SearchModulesQuery, SearchResult } from '../../../types';
import { CacheKeys, CacheTTL } from '../../../types';
import { generateEmbedding } from '../../../lib/embeddings';

export async function searchModules(c: Context<{ Bindings: Env }>) {
  const query: SearchModulesQuery = {
    q: c.req.query('q') || '',
    limit: parseInt(c.req.query('limit') || '20'),
    offset: parseInt(c.req.query('offset') || '0'),
    mode: (c.req.query('mode') || 'hybrid') as 'keyword' | 'semantic' | 'hybrid',
  };

  // Validate query
  if (!query.q || query.q.trim().length < 2) {
    return c.json({
      error: 'Query must be at least 2 characters long',
      timestamp: new Date().toISOString(),
    }, 400);
  }

  // Validate parameters
  if (query.limit < 1 || query.limit > 50) {
    query.limit = 20;
  }
  if (query.offset < 0) {
    query.offset = 0;
  }

  // Generate cache key (include mode)
  const cacheKey = CacheKeys.search(`${query.q}:${query.limit}:${query.offset}:${query.mode}`);

  // Check cache (only if KV binding configured)
  if (c.env.CACHE) {
    try {
      const cached = await c.env.CACHE.get(cacheKey, 'json');
      if (cached) {
        c.header('X-Cache', 'HIT');
        return c.json(cached);
      }
    } catch (error) {
      console.warn('Cache read error:', error);
    }
  }

  try {
    let results: any[] = [];
    let totalCount = 0;

    // Execute searches based on mode
    if (query.mode === 'keyword' || query.mode === 'hybrid') {
      // Escape special characters for FTS5
      const searchTerm = query.q.replace(/['"]/g, '');

      // Perform FTS5 search with ranking
      const searchStmt = c.env.MODULES_DB.prepare(`
        SELECT
          m.id,
          m.path,
          m.name,
          m.namespace,
          m.description,
          m.created_at,
          m.updated_at,
          snippet(modules_fts, 2, '<mark>', '</mark>', '...', 32) as snippet,
          rank as relevance_score
        FROM modules m
        JOIN modules_fts ON m.id = modules_fts.rowid
        WHERE modules_fts MATCH ?
        ORDER BY rank
        LIMIT ? OFFSET ?
      `);

      const ftsResults = await searchStmt.bind(searchTerm, query.limit, query.offset).all();
      results = ftsResults.results || [];

      // Get total count for pagination
      const countStmt = c.env.MODULES_DB.prepare(`
        SELECT COUNT(*) as total
        FROM modules_fts
        WHERE modules_fts MATCH ?
      `);

      const countResult = await countStmt.bind(searchTerm).first();
      totalCount = countResult?.total || 0;
    }

    // Semantic search
    if ((query.mode === 'semantic' || query.mode === 'hybrid') &&
        c.env.AI && c.env.VECTORIZE) {
      try {
        // Generate query embedding
        const queryEmbedding = await generateEmbedding(c.env.AI, query.q);

        // Query Vectorize
        const vectorResults = await c.env.VECTORIZE.query(queryEmbedding, {
          topK: query.limit,
          returnMetadata: true,
        });

        // Fetch full module data for vector results
        if (vectorResults.matches.length > 0) {
          const vectorPaths = vectorResults.matches.map(m => m.id);
          const placeholders = vectorPaths.map(() => '?').join(',');

          const modulesResult = await c.env.MODULES_DB.prepare(`
            SELECT
              m.id,
              m.path,
              m.name,
              m.namespace,
              m.description,
              m.created_at,
              m.updated_at
            FROM modules m
            WHERE m.path IN (${placeholders})
          `).bind(...vectorPaths).all();

          const modulesById = new Map(
            modulesResult.results.map((m: any) => [m.path, m])
          );

          const semanticResults = vectorResults.matches.map(match => ({
            ...modulesById.get(match.id),
            relevance_score: match.score,
            match_type: 'semantic',
          }));

          // Merge results for hybrid mode
          if (query.mode === 'hybrid') {
            // Deduplicate by path, preferring higher relevance
            const merged = new Map();
            [...results, ...semanticResults].forEach((r: any) => {
              if (!merged.has(r.path) ||
                  r.relevance_score > merged.get(r.path).relevance_score) {
                merged.set(r.path, r);
              }
            });
            results = Array.from(merged.values())
              .sort((a: any, b: any) => b.relevance_score - a.relevance_score)
              .slice(0, query.limit);
            totalCount = Math.max(totalCount, merged.size);
          } else {
            results = semanticResults;
            totalCount = vectorResults.matches.length;
          }
        }
      } catch (error) {
        console.warn('Semantic search failed, falling back to keyword:', error);
        // Continue with keyword results if semantic fails
      }
    }

    const response: SearchResult & { pagination: any; mode?: string } = {
      query: query.q,
      mode: query.mode,
      results: results || [],
      count: totalCount,
      pagination: {
        total: totalCount,
        limit: query.limit,
        offset: query.offset,
        hasMore: query.offset + query.limit < totalCount,
      },
      timestamp: new Date().toISOString(),
    };

    // Cache the response (only if KV binding configured)
    if (c.env.CACHE) {
      try {
        await c.env.CACHE.put(
          cacheKey,
          JSON.stringify(response),
          { expirationTtl: CacheTTL.search }
        );
      } catch (error) {
        console.warn('Cache write error:', error);
      }
    }

    // Track search analytics if enabled
    if (c.env.ANALYTICS) {
      try {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ['search', query.mode],
          blobs: [query.q.toLowerCase()],
          doubles: [totalCount, Date.now()],
        });
      } catch (error) {
        console.warn('Analytics write error:', error);
      }
    }

    c.header('X-Cache', 'MISS');
    return c.json(response);

  } catch (error) {
    console.error('Search error:', error);

    // Fallback to LIKE search if FTS5 fails
    try {
      const fallbackStmt = c.env.MODULES_DB.prepare(`
        SELECT
          id,
          path,
          name,
          namespace,
          description,
          created_at,
          updated_at
        FROM modules
        WHERE
          name LIKE ? OR
          namespace LIKE ? OR
          description LIKE ?
        ORDER BY name
        LIMIT ? OFFSET ?
      `);

      const searchPattern = `%${query.q}%`;
      const fallbackResults = await fallbackStmt.bind(
        searchPattern,
        searchPattern,
        searchPattern,
        query.limit,
        query.offset
      ).all();

      const response = {
        query: query.q,
        results: fallbackResults.results || [],
        count: fallbackResults.results?.length || 0,
        fallback: true,
        timestamp: new Date().toISOString(),
      };

      return c.json(response);

    } catch (fallbackError) {
      console.error('Fallback search error:', fallbackError);
      return c.json({
        error: 'Search service temporarily unavailable',
        timestamp: new Date().toISOString(),
      }, 503);
    }
  }
}