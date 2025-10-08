/**
 * List modules handler
 * Returns paginated list of modules with optional filtering
 */

import type { Context } from 'hono';
import type { Env, Module, ListModulesQuery } from '../../../types';
import { CacheKeys, CacheTTL } from '../../../types';

export async function listModules(c: Context<{ Bindings: Env }>) {
  const query: ListModulesQuery = {
    namespace: c.req.query('namespace'),
    limit: parseInt(c.req.query('limit') || '50'),
    offset: parseInt(c.req.query('offset') || '0'),
    sort: c.req.query('sort') as ListModulesQuery['sort'] || 'name',
  };

  // Validate parameters
  if (query.limit < 1 || query.limit > 100) {
    query.limit = 50;
  }
  if (query.offset < 0) {
    query.offset = 0;
  }

  // Generate cache key
  const cacheKey = CacheKeys.moduleList(JSON.stringify(query));

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
    // Build SQL query
    let sql = `
      SELECT
        m.id,
        m.path,
        m.name,
        m.namespace,
        m.description,
        m.created_at,
        m.updated_at,
        COUNT(DISTINCT hu.hostname_hash) as usage_count
      FROM modules m
      LEFT JOIN host_usage hu ON m.path = hu.module_path
    `;

    const params: any[] = [];

    // Add namespace filter if provided
    if (query.namespace) {
      sql += ' WHERE m.namespace = ?';
      params.push(query.namespace);
    }

    sql += ' GROUP BY m.id';

    // Add sorting
    switch (query.sort) {
      case 'usage':
        sql += ' ORDER BY usage_count DESC, m.name ASC';
        break;
      case 'updated':
        sql += ' ORDER BY m.updated_at DESC';
        break;
      case 'namespace':
        sql += ' ORDER BY m.namespace ASC, m.name ASC';
        break;
      default:
        sql += ' ORDER BY m.name ASC';
    }

    // Add pagination
    sql += ' LIMIT ? OFFSET ?';
    params.push(query.limit, query.offset);

    // Execute query
    const stmt = c.env.MODULES_DB.prepare(sql);
    const result = await stmt.bind(...params).all();

    // Get total count for pagination
    let countSql = 'SELECT COUNT(*) as total FROM modules';
    const countParams: any[] = [];

    if (query.namespace) {
      countSql += ' WHERE namespace = ?';
      countParams.push(query.namespace);
    }

    const countStmt = c.env.MODULES_DB.prepare(countSql);
    const countResult = await countStmt.bind(...countParams).first();

    const response = {
      modules: result.results,
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
          { expirationTtl: CacheTTL.moduleList }
        );
      } catch (error) {
        console.warn('Cache write error:', error);
      }
    }

    c.header('X-Cache', 'MISS');
    return c.json(response);

  } catch (error) {
    console.error('Database error:', error);
    return c.json({
      error: 'Failed to fetch modules',
      timestamp: new Date().toISOString(),
    }, 500);
  }
}