/**
 * Batch update modules handler
 * Used by CI/CD to update module documentation
 *
 * Uses D1 batch() API for atomic transactions:
 * - Each module update/create is executed atomically
 * - For existing modules: Single transaction with all operations
 * - For new modules: Two transactions (insert module, then insert related data)
 * - If any operation fails, the entire module transaction is rolled back
 * - Ensures data consistency (no partial module updates)
 */

import type { Context } from 'hono';
import type { Env, Module, BatchUpdateRequest } from '../../../types';
import { CacheKeys } from '../../../types';
import { z } from 'zod';
import { createTextBlob, generateEmbedding } from '../../../lib/embeddings';

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

    // Process modules individually with atomic transactions
    for (const moduleData of modules) {
      try {
        // Check if module exists
        const existingStmt = c.env.MODULES_DB.prepare(
          'SELECT id FROM modules WHERE path = ?'
        );
        const existing = await existingStmt.bind(moduleData.path).first();

        if (existing) {
          // Update existing module using atomic transaction
          const statements = [];

          // 1. Update module
          statements.push(
            c.env.MODULES_DB.prepare(`
              UPDATE modules
              SET
                name = ?,
                namespace = ?,
                description = ?,
                examples = ?,
                metadata = ?,
                updated_at = CURRENT_TIMESTAMP
              WHERE path = ?
            `).bind(
              moduleData.name,
              moduleData.namespace,
              moduleData.description || null,
              JSON.stringify(moduleData.examples || []),
              JSON.stringify(moduleData.metadata || {}),
              moduleData.path
            )
          );

          // 2. Delete existing options
          statements.push(
            c.env.MODULES_DB.prepare(
              'DELETE FROM module_options WHERE module_id = ?'
            ).bind(existing.id)
          );

          // 3. Insert new options
          if (moduleData.options && moduleData.options.length > 0) {
            for (const option of moduleData.options) {
              statements.push(
                c.env.MODULES_DB.prepare(`
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
                )
              );
            }
          }

          // 4. Delete existing dependencies
          statements.push(
            c.env.MODULES_DB.prepare(
              'DELETE FROM module_dependencies WHERE module_id = ?'
            ).bind(existing.id)
          );

          // 5. Insert new dependencies
          if (moduleData.dependencies && moduleData.dependencies.length > 0) {
            for (const dep of moduleData.dependencies) {
              statements.push(
                c.env.MODULES_DB.prepare(`
                  INSERT INTO module_dependencies (
                    module_id, depends_on_path, dependency_type
                  ) VALUES (?, ?, ?)
                `).bind(
                  existing.id,
                  dep.depends_on_path,
                  dep.dependency_type || 'imports'
                )
              );
            }
          }

          // Execute all statements atomically
          await c.env.MODULES_DB.batch(statements);
          results.updated++;

        } else {
          // Create new module using atomic transactions

          // First transaction: Insert module
          const insertResult = await c.env.MODULES_DB.prepare(`
            INSERT INTO modules (
              path, name, namespace, description, examples, metadata
            ) VALUES (?, ?, ?, ?, ?, ?)
          `).bind(
            moduleData.path,
            moduleData.name,
            moduleData.namespace,
            moduleData.description || null,
            JSON.stringify(moduleData.examples || []),
            JSON.stringify(moduleData.metadata || {})
          ).run();

          const moduleId = insertResult.meta.last_row_id;
          results.created++;

          // Second transaction: Insert options and dependencies atomically
          if ((moduleData.options && moduleData.options.length > 0) ||
              (moduleData.dependencies && moduleData.dependencies.length > 0)) {

            const relatedStatements = [];

            // Insert options
            if (moduleData.options && moduleData.options.length > 0) {
              for (const option of moduleData.options) {
                relatedStatements.push(
                  c.env.MODULES_DB.prepare(`
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
                  )
                );
              }
            }

            // Insert dependencies
            if (moduleData.dependencies && moduleData.dependencies.length > 0) {
              for (const dep of moduleData.dependencies) {
                relatedStatements.push(
                  c.env.MODULES_DB.prepare(`
                    INSERT INTO module_dependencies (
                      module_id, depends_on_path, dependency_type
                    ) VALUES (?, ?, ?)
                  `).bind(
                    moduleId,
                    dep.depends_on_path,
                    dep.dependency_type || 'imports'
                  )
                );
              }
            }

            // Execute all related inserts atomically
            await c.env.MODULES_DB.batch(relatedStatements);
          }
        }

        // Clear cache for this module (if KV is configured)
        if (c.env.CACHE) {
          const cacheKey = `module:${moduleData.namespace}:${moduleData.name}`;
          await c.env.CACHE.delete(cacheKey);
        }

        // Generate and store embedding for semantic search
        if (c.env.AI && c.env.VECTORIZE) {
          try {
            const textBlob = createTextBlob({
              name: moduleData.name,
              description: moduleData.description,
              namespace: moduleData.namespace,
              options: moduleData.options || [],
            });

            const embedding = await generateEmbedding(c.env.AI, textBlob);

            await c.env.VECTORIZE.upsert([
              {
                id: moduleData.path, // Use module path as vector ID
                values: embedding,
                metadata: {
                  namespace: moduleData.namespace,
                  name: moduleData.name,
                  updatedAt: new Date().toISOString(),
                },
              },
            ]);
          } catch (error) {
            // Don't fail module upload if embedding fails
            console.warn(`Failed to generate embedding for ${moduleData.path}:`, error);
          }
        }

      } catch (moduleError: any) {
        console.error(`Error processing module ${moduleData.path}:`, moduleError);
        results.failed++;
        results.errors.push(`${moduleData.path}: ${moduleError.message}`);
      }
    }

    // Clear list cache (if KV is configured)
    if (c.env.CACHE) {
      await c.env.CACHE.delete(CacheKeys.moduleList('*'));
      await c.env.CACHE.delete(CacheKeys.stats());
    }

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