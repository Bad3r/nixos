/**
 * Search modules handler - Using AI Search
 * Supports four search modes:
 * - keyword: Traditional keyword search using D1 FTS5
 * - semantic: AI-powered semantic search
 * - hybrid: Combined keyword and semantic search (default)
 * - ai: AI-powered search with generated response
 */

import type { Context } from 'hono';
import type { Env, SearchModulesQuery, SearchResult } from '../../../types';
import { CacheKeys, CacheTTL } from '../../../types';
import { performHybridSearch, trackSearchAnalytics } from '../../../services/ai-search';

export async function searchModules(c: Context<{ Bindings: Env }>) {
  const query: SearchModulesQuery = {
    q: c.req.query('q') || '',
    limit: parseInt(c.req.query('limit') || '20'),
    offset: parseInt(c.req.query('offset') || '0'),
    mode: (c.req.query('mode') || 'hybrid') as 'keyword' | 'semantic' | 'hybrid',
  };

  // Support new 'ai' mode for AI-powered responses
  const aiMode = c.req.query('ai') === 'true' || query.mode === 'ai';
  const model = c.req.query('model'); // Optional model override

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

  // Generate cache key (include AI mode and model)
  const cacheKey = CacheKeys.search(
    `${query.q}:${query.limit}:${query.offset}:${query.mode}:${aiMode}:${model || 'default'}`
  );

  // Check cache (only if KV binding configured)
  if (c.env.CACHE) {
    try {
      const cached = await c.env.CACHE.get(cacheKey, 'json');
      if (cached) {
        c.header('X-Cache', 'HIT');
        c.header('X-Search-Version', 'ai-search');
        return c.json(cached);
      }
    } catch (error) {
      console.warn('Cache read error:', error);
    }
  }

  try {
    // Check if AI Search is available
    const useAISearch = c.env.AI && c.env.AI_SEARCH;

    if (!useAISearch && (query.mode === 'semantic' || query.mode === 'hybrid' || aiMode)) {
      // Fallback to keyword search if AI Search not available
      console.warn('AI Search not configured, falling back to keyword search');
      query.mode = 'keyword';
    }

    let response: any;

    if (useAISearch && query.mode !== 'keyword') {
      // Use AI Search for semantic, hybrid, or AI-powered search
      const searchResult = await performHybridSearch(c.env, query.q, {
        limit: query.limit,
        mode: aiMode ? 'ai' : query.mode,
        generateResponse: aiMode,
        model: model,
      });

      // Fetch full module data for the results
      const modulePaths = searchResult.results.map(r => r.id);
      let modules: any[] = [];

      if (modulePaths.length > 0) {
        const placeholders = modulePaths.map(() => '?').join(',');
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
        `).bind(...modulePaths).all();

        const modulesById = new Map(
          modulesResult.results.map((m: any) => [m.path, m])
        );

        modules = searchResult.results.map(result => ({
          ...modulesById.get(result.id),
          relevance_score: result.score,
          snippet: result.snippet,
          match_type: 'ai_search',
        })).filter(Boolean); // Filter out any null results
      }

      response = {
        query: query.q,
        mode: searchResult.mode,
        results: modules,
        count: modules.length,
        ai_response: searchResult.aiResponse,
        query_rewritten: searchResult.queryRewritten,
        search_version: 'ai-search',
        pagination: {
          total: modules.length,
          limit: query.limit,
          offset: query.offset,
          hasMore: false, // AI Search doesn't support traditional pagination
        },
        timestamp: new Date().toISOString(),
      };

      // Track analytics
      trackSearchAnalytics(c.env, query.q, modules.length, searchResult.mode);

    } else {
      // Fallback to keyword search using FTS5
      const searchTerm = query.q.replace(/['"]/g, '');

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

      // Get total count for pagination
      const countStmt = c.env.MODULES_DB.prepare(`
        SELECT COUNT(*) as total
        FROM modules_fts
        WHERE modules_fts MATCH ?
      `);

      const countResult = await countStmt.bind(searchTerm).first();
      const totalCount = countResult?.total || 0;

      response = {
        query: query.q,
        mode: 'keyword',
        results: ftsResults.results || [],
        count: totalCount,
        search_version: 'fts5',
        pagination: {
          total: totalCount,
          limit: query.limit,
          offset: query.offset,
          hasMore: query.offset + query.limit < totalCount,
        },
        timestamp: new Date().toISOString(),
      };

      // Track analytics
      if (c.env.ANALYTICS) {
        try {
          c.env.ANALYTICS.writeDataPoint({
            indexes: ['search', 'keyword'],
            blobs: [query.q.toLowerCase()],
            doubles: [totalCount, Date.now()],
          });
        } catch (error) {
          console.warn('Analytics write error:', error);
        }
      }
    }

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

    c.header('X-Cache', 'MISS');
    c.header('X-Search-Version', response.search_version);
    return c.json(response);

  } catch (error) {
    console.error('Search error:', error);

    // Fallback to LIKE search if everything fails
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
        search_version: 'fallback',
        timestamp: new Date().toISOString(),
      };

      c.header('X-Search-Version', 'fallback');
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