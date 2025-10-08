/**
 * Backfill embeddings for existing modules
 * Protected endpoint for admin use
 */
import type { Context } from 'hono';
import type { Env } from '../../../types';
import { createTextBlob, generateEmbedding } from '../../../lib/embeddings';

export async function backfillEmbeddings(c: Context<{ Bindings: Env }>) {
  // Check AI and Vectorize bindings
  if (!c.env.AI || !c.env.VECTORIZE) {
    return c.json({
      error: 'AI or Vectorize binding not configured',
    }, 500);
  }

  try {
    // Fetch all modules
    const result = await c.env.MODULES_DB.prepare(`
      SELECT m.id, m.path, m.name, m.namespace, m.description
      FROM modules m
      ORDER BY m.id
    `).all();

    const modules = result.results;
    let processed = 0;
    let failed = 0;

    for (const module of modules) {
      try {
        // Fetch options for this module
        const optionsResult = await c.env.MODULES_DB.prepare(`
          SELECT name, description FROM module_options WHERE module_id = ?
        `).bind(module.id).all();

        const textBlob = createTextBlob({
          name: module.name as string,
          description: module.description as string,
          namespace: module.namespace as string,
          options: optionsResult.results as any[],
        });

        const embedding = await generateEmbedding(c.env.AI, textBlob);

        await c.env.VECTORIZE.upsert([
          {
            id: module.path as string,
            values: embedding,
            metadata: {
              namespace: module.namespace,
              name: module.name,
              backfilled: true,
              updatedAt: new Date().toISOString(),
            },
          },
        ]);

        processed++;
      } catch (error) {
        console.error(`Failed to process module ${module.path}:`, error);
        failed++;
      }
    }

    return c.json({
      success: true,
      stats: {
        total: modules.length,
        processed,
        failed,
      },
      timestamp: new Date().toISOString(),
    });

  } catch (error: any) {
    return c.json({
      error: 'Backfill failed',
      message: error.message,
    }, 500);
  }
}
