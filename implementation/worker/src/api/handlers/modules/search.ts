/**
 * Search modules handler
 * Uses FTS5 for full-text search (Phase 1 MVP)
 * TODO: Add Vectorize for semantic search in Phase 2
 */

import type { Context } from 'hono';
import type { Env, SearchModulesQuery, SearchResult } from '../../../types';
import { CacheKeys, CacheTTL } from '../../../types';

export async function searchModules(c: Context<{ Bindings: Env }>) {
  const query: SearchModulesQuery = {
    q: c.req.query('q') || '',
    limit: parseInt(c.req.query('limit') || '20'),
    offset: parseInt(c.req.query('offset') || '0'),
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

  // Generate cache key
  const cacheKey = CacheKeys.search(`${query.q}:${query.limit}:${query.offset}`);

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

    const results = await searchStmt.bind(searchTerm, query.limit, query.offset).all();

    // Get total count for pagination
    const countStmt = c.env.MODULES_DB.prepare(`
      SELECT COUNT(*) as total
      FROM modules_fts
      WHERE modules_fts MATCH ?
    `);

    const countResult = await countStmt.bind(searchTerm).first();

    const response: SearchResult & { pagination: any } = {
      query: query.q,
      results: results.results || [],
      count: countResult?.total || 0,
      pagination: {
        total: countResult?.total || 0,
        limit: query.limit,
        offset: query.offset,
        hasMore: query.offset + query.limit < (countResult?.total || 0),
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
          indexes: ['search'],
          blobs: [query.q.toLowerCase()],
          doubles: [countResult?.total || 0, Date.now()],
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