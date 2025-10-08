/**
 * Get single module handler
 * Returns detailed module information including options and dependencies
 */

import type { Context } from 'hono';
import type { Env, ModuleWithOptions } from '../../../types';
import { CacheKeys, CacheTTL } from '../../../types';

export async function getModule(c: Context<{ Bindings: Env }>) {
  const namespace = c.req.param('namespace');
  const name = c.req.param('name');

  if (!namespace || !name) {
    return c.json({
      error: 'Namespace and name are required',
      timestamp: new Date().toISOString(),
    }, 400);
  }

  // Generate cache key
  const cacheKey = CacheKeys.module(namespace, name);

  // Check cache
  try {
    const cached = await c.env.CACHE.get(cacheKey, 'json');
    if (cached) {
      c.header('X-Cache', 'HIT');
      return c.json(cached);
    }
  } catch (error) {
    console.warn('Cache read error:', error);
  }

  try {
    // Fetch module
    const moduleStmt = c.env.MODULES_DB.prepare(`
      SELECT
        m.*,
        COUNT(DISTINCT hu.hostname_hash) as usage_count
      FROM modules m
      LEFT JOIN host_usage hu ON m.path = hu.module_path
      WHERE m.namespace = ? AND m.name = ?
      GROUP BY m.id
    `);

    const module = await moduleStmt.bind(namespace, name).first<ModuleWithOptions>();

    if (!module) {
      return c.json({
        error: 'Module not found',
        namespace,
        name,
        timestamp: new Date().toISOString(),
      }, 404);
    }

    // Fetch options
    const optionsStmt = c.env.MODULES_DB.prepare(`
      SELECT * FROM module_options
      WHERE module_id = ?
      ORDER BY name
    `);

    const options = await optionsStmt.bind(module.id).all();

    // Fetch dependencies
    const depsStmt = c.env.MODULES_DB.prepare(`
      SELECT
        md.*,
        m2.name as depends_on_name,
        m2.namespace as depends_on_namespace
      FROM module_dependencies md
      LEFT JOIN modules m2 ON md.depends_on_path = m2.path
      WHERE md.module_id = ?
      ORDER BY md.depends_on_path
    `);

    const dependencies = await depsStmt.bind(module.id).all();

    // Parse JSON fields
    if (module.examples && typeof module.examples === 'string') {
      try {
        module.examples = JSON.parse(module.examples);
      } catch {}
    }

    if (module.metadata && typeof module.metadata === 'string') {
      try {
        module.metadata = JSON.parse(module.metadata);
      } catch {}
    }

    // Parse option JSON fields
    const parsedOptions = options.results.map((opt: any) => {
      if (opt.default_value && typeof opt.default_value === 'string') {
        try {
          opt.default_value = JSON.parse(opt.default_value);
        } catch {}
      }
      if (opt.example && typeof opt.example === 'string') {
        try {
          opt.example = JSON.parse(opt.example);
        } catch {}
      }
      return opt;
    });

    const response = {
      module: {
        ...module,
        options: parsedOptions,
        dependencies: dependencies.results,
      },
      timestamp: new Date().toISOString(),
    };

    // Cache the response
    try {
      await c.env.CACHE.put(
        cacheKey,
        JSON.stringify(response),
        { expirationTtl: CacheTTL.module }
      );
    } catch (error) {
      console.warn('Cache write error:', error);
    }

    // Also store in R2 for large content if needed
    if (JSON.stringify(response).length > 25000) { // If larger than 25KB
      try {
        await c.env.DOCUMENTS.put(
          `modules/${namespace}/${name}.json`,
          JSON.stringify(response),
          {
            httpMetadata: {
              contentType: 'application/json',
            },
            customMetadata: {
              namespace,
              name,
              updatedAt: new Date().toISOString(),
            },
          }
        );
      } catch (error) {
        console.warn('R2 write error:', error);
      }
    }

    c.header('X-Cache', 'MISS');
    return c.json(response);

  } catch (error) {
    console.error('Database error:', error);
    return c.json({
      error: 'Failed to fetch module',
      namespace,
      name,
      timestamp: new Date().toISOString(),
    }, 500);
  }
}