/**
 * Batch update modules handler
 * Used by CI/CD to update module documentation
 */

import type { Context } from 'hono';
import type { Env, Module, BatchUpdateRequest } from '../../../types';
import { z } from 'zod';

// Validation schema
const ModuleSchema = z.object({
  path: z.string().min(1),
  name: z.string().min(1),
  namespace: z.string().min(1),
  description: z.string().optional(),
  examples: z.array(z.string()).optional(),
  metadata: z.record(z.any()).optional(),
  options: z.array(z.object({
    name: z.string(),
    type: z.string(),
    default_value: z.any().optional(),
    description: z.string().optional(),
    example: z.any().optional(),
    read_only: z.boolean().optional(),
    internal: z.boolean().optional(),
  })).optional(),
  dependencies: z.array(z.object({
    depends_on_path: z.string(),
    dependency_type: z.string().optional(),
  })).optional(),
});

const BatchUpdateSchema = z.object({
  modules: z.array(ModuleSchema).max(100), // Limit batch size
});

export async function batchUpdateModules(c: Context<{ Bindings: Env }>) {
  try {
    // Parse and validate request body
    const body = await c.req.json();
    const validation = BatchUpdateSchema.safeParse(body);

    if (!validation.success) {
      return c.json({
        error: 'Invalid request data',
        details: validation.error.flatten(),
        timestamp: new Date().toISOString(),
      }, 400);
    }

    const { modules } = validation.data;

    // Start a transaction-like batch operation
    const results = {
      updated: 0,
      created: 0,
      failed: 0,
      errors: [] as string[],
    };

    // Process modules in smaller batches for D1
    const BATCH_SIZE = parseInt(c.env.MAX_BATCH_SIZE || '10');

    for (let i = 0; i < modules.length; i += BATCH_SIZE) {
      const batch = modules.slice(i, i + BATCH_SIZE);

      try {
        // Process each module in the batch
        for (const moduleData of batch) {
          try {
            // Check if module exists
            const existingStmt = c.env.MODULES_DB.prepare(
              'SELECT id FROM modules WHERE path = ?'
            );
            const existing = await existingStmt.bind(moduleData.path).first();

            if (existing) {
              // Update existing module
              const updateStmt = c.env.MODULES_DB.prepare(`
                UPDATE modules
                SET
                  name = ?,
                  namespace = ?,
                  description = ?,
                  examples = ?,
                  metadata = ?,
                  updated_at = CURRENT_TIMESTAMP
                WHERE path = ?
              `);

              await updateStmt.bind(
                moduleData.name,
                moduleData.namespace,
                moduleData.description || null,
                JSON.stringify(moduleData.examples || []),
                JSON.stringify(moduleData.metadata || {}),
                moduleData.path
              ).run();

              results.updated++;

              // Update options if provided
              if (moduleData.options && moduleData.options.length > 0) {
                // Delete existing options
                await c.env.MODULES_DB.prepare(
                  'DELETE FROM module_options WHERE module_id = ?'
                ).bind(existing.id).run();

                // Insert new options
                for (const option of moduleData.options) {
                  await c.env.MODULES_DB.prepare(`
                    INSERT INTO module_options (
                      module_id, name, type, default_value,
                      description, example, read_only, internal
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                  `).bind(
                    existing.id,
                    option.name,
                    option.type,
                    JSON.stringify(option.default_value),
                    option.description || null,
                    JSON.stringify(option.example),
                    option.read_only ? 1 : 0,
                    option.internal ? 1 : 0
                  ).run();
                }
              }

              // Update dependencies if provided
              if (moduleData.dependencies && moduleData.dependencies.length > 0) {
                // Delete existing dependencies
                await c.env.MODULES_DB.prepare(
                  'DELETE FROM module_dependencies WHERE module_id = ?'
                ).bind(existing.id).run();

                // Insert new dependencies
                for (const dep of moduleData.dependencies) {
                  await c.env.MODULES_DB.prepare(`
                    INSERT INTO module_dependencies (
                      module_id, depends_on_path, dependency_type
                    ) VALUES (?, ?, ?)
                  `).bind(
                    existing.id,
                    dep.depends_on_path,
                    dep.dependency_type || 'imports'
                  ).run();
                }
              }

            } else {
              // Create new module
              const insertStmt = c.env.MODULES_DB.prepare(`
                INSERT INTO modules (
                  path, name, namespace, description, examples, metadata
                ) VALUES (?, ?, ?, ?, ?, ?)
              `);

              const result = await insertStmt.bind(
                moduleData.path,
                moduleData.name,
                moduleData.namespace,
                moduleData.description || null,
                JSON.stringify(moduleData.examples || []),
                JSON.stringify(moduleData.metadata || {})
              ).run();

              const moduleId = result.meta.last_row_id;
              results.created++;

              // Insert options if provided
              if (moduleData.options && moduleData.options.length > 0) {
                for (const option of moduleData.options) {
                  await c.env.MODULES_DB.prepare(`
                    INSERT INTO module_options (
                      module_id, name, type, default_value,
                      description, example, read_only, internal
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                  `).bind(
                    moduleId,
                    option.name,
                    option.type,
                    JSON.stringify(option.default_value),
                    option.description || null,
                    JSON.stringify(option.example),
                    option.read_only ? 1 : 0,
                    option.internal ? 1 : 0
                  ).run();
                }
              }

              // Insert dependencies if provided
              if (moduleData.dependencies && moduleData.dependencies.length > 0) {
                for (const dep of moduleData.dependencies) {
                  await c.env.MODULES_DB.prepare(`
                    INSERT INTO module_dependencies (
                      module_id, depends_on_path, dependency_type
                    ) VALUES (?, ?, ?)
                  `).bind(
                    moduleId,
                    dep.depends_on_path,
                    dep.dependency_type || 'imports'
                  ).run();
                }
              }
            }

            // Clear cache for this module
            const cacheKey = `module:${moduleData.namespace}:${moduleData.name}`;
            await c.env.CACHE.delete(cacheKey);

          } catch (moduleError: any) {
            console.error(`Error processing module ${moduleData.path}:`, moduleError);
            results.failed++;
            results.errors.push(`${moduleData.path}: ${moduleError.message}`);
          }
        }

      } catch (batchError: any) {
        console.error('Batch processing error:', batchError);
        results.failed += batch.length;
        results.errors.push(`Batch error: ${batchError.message}`);
      }
    }

    // Clear list cache
    await c.env.CACHE.delete(CacheKeys.moduleList('*'));
    await c.env.CACHE.delete(CacheKeys.stats());

    // Log to analytics if enabled
    if (c.env.ANALYTICS) {
      try {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ['batch_update'],
          blobs: ['modules'],
          doubles: [results.updated, results.created, results.failed, Date.now()],
        });
      } catch (error) {
        console.warn('Analytics write error:', error);
      }
    }

    const success = results.failed === 0;
    const status = success ? 200 : 207; // 207 Multi-Status for partial success

    return c.json({
      success,
      results,
      timestamp: new Date().toISOString(),
    }, status);

  } catch (error: any) {
    console.error('Batch update error:', error);
    return c.json({
      error: 'Failed to update modules',
      message: error.message,
      timestamp: new Date().toISOString(),
    }, 500);
  }
}

// Helper to clear all caches
async function clearAllCaches(env: Env) {
  // This would ideally list and delete all keys, but KV doesn't support
  // listing keys efficiently. For MVP, we just clear known patterns.
  const patterns = [
    'module:*',
    'modules:list:*',
    'search:*',
    'stats:*',
  ];

  // Note: This is a simplified approach. In production, you might want
  // to track cache keys in a separate index or use cache tags.
}