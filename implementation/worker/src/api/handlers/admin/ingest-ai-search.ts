/**
 * AI Search Ingestion Handler
 * Processes and indexes modules into AI Search for automatic embedding generation
 * and hybrid search capabilities
 */

import type { Context } from 'hono';
import type { Env, ModuleWithOptions } from '../../../types';
import { ingestModules, clearSearchIndex } from '../../../services/ai-search';

/**
 * Ingest all modules into AI Search
 * This replaces the manual embedding generation with AI Search's automatic processing
 */
export async function ingestToAISearch(c: Context<{ Bindings: Env }>) {
  // Check if AI Search is configured
  if (!c.env.AI || !c.env.AI_SEARCH) {
    return c.json({
      error: 'AI Search is not configured',
      message: 'Please configure AI Search bindings in wrangler.jsonc',
      timestamp: new Date().toISOString(),
    }, 503);
  }

  const batchSize = parseInt(c.req.query('batch_size') || '100');
  const clearIndex = c.req.query('clear') === 'true';

  try {
    // Optionally clear the index first (for full reindex)
    if (clearIndex) {
      console.log('Clearing AI Search index for full reindex...');
      await clearSearchIndex(c.env);
    }

    // Get total count of modules
    const countResult = await c.env.MODULES_DB.prepare(
      'SELECT COUNT(*) as total FROM modules'
    ).first();
    const totalModules = countResult?.total || 0;

    console.log(`Starting AI Search ingestion for ${totalModules} modules...`);

    let processedTotal = 0;
    let offset = 0;
    const errors: string[] = [];
    const startTime = Date.now();

    // Process modules in batches
    while (offset < totalModules) {
      // Fetch batch of modules with their options and dependencies
      const modulesResult = await c.env.MODULES_DB.prepare(`
        SELECT
          m.id,
          m.path,
          m.name,
          m.namespace,
          m.description,
          m.examples,
          m.metadata,
          m.created_at,
          m.updated_at
        FROM modules m
        ORDER BY m.id
        LIMIT ? OFFSET ?
      `).bind(batchSize, offset).all();

      const modules = modulesResult.results || [];

      // For each module, fetch options and dependencies
      const modulesWithDetails: ModuleWithOptions[] = await Promise.all(
        modules.map(async (module: any) => {
          // Fetch options
          const optionsResult = await c.env.MODULES_DB.prepare(`
            SELECT
              id,
              module_id,
              name,
              type,
              default_value,
              description,
              example,
              read_only,
              internal
            FROM module_options
            WHERE module_id = ?
            ORDER BY name
          `).bind(module.id).all();

          // Fetch dependencies
          const depsResult = await c.env.MODULES_DB.prepare(`
            SELECT
              id,
              module_id,
              depends_on_path,
              dependency_type
            FROM module_dependencies
            WHERE module_id = ?
          `).bind(module.id).all();

          // Get usage count
          const usageResult = await c.env.MODULES_DB.prepare(`
            SELECT COUNT(*) as usage_count
            FROM host_modules
            WHERE module_path = ?
          `).bind(module.path).first();

          return {
            ...module,
            options: optionsResult.results || [],
            dependencies: depsResult.results || [],
            usage_count: usageResult?.usage_count || 0,
            examples: module.examples ? JSON.parse(module.examples) : [],
            metadata: module.metadata ? JSON.parse(module.metadata) : {},
          };
        })
      );

      // Ingest batch into AI Search
      const batchResult = await ingestModules(c.env, modulesWithDetails);

      processedTotal += batchResult.processed;
      errors.push(...batchResult.errors);

      // Log progress
      const progress = Math.round((processedTotal / totalModules) * 100);
      console.log(`Ingestion progress: ${processedTotal}/${totalModules} (${progress}%)`);

      // Update offset for next batch
      offset += batchSize;

      // Add a small delay between batches to avoid rate limiting
      if (offset < totalModules) {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }

    const duration = Date.now() - startTime;
    const success = errors.length === 0;

    // Log results
    const result = {
      success,
      message: success
        ? 'AI Search ingestion completed successfully'
        : 'AI Search ingestion completed with errors',
      stats: {
        total_modules: totalModules,
        processed: processedTotal,
        failed: errors.length,
        duration_ms: duration,
        modules_per_second: Math.round((processedTotal / duration) * 1000),
      },
      errors: errors.slice(0, 10), // Limit errors in response
      timestamp: new Date().toISOString(),
    };

    // Track analytics
    if (c.env.ANALYTICS) {
      try {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ['ai_search_ingestion'],
          blobs: [success ? 'success' : 'partial'],
          doubles: [processedTotal, duration],
        });
      } catch (error) {
        console.warn('Analytics write error:', error);
      }
    }

    return c.json(result, success ? 200 : 207);

  } catch (error) {
    console.error('AI Search ingestion error:', error);

    return c.json({
      error: 'Ingestion failed',
      message: error instanceof Error ? error.message : String(error),
      timestamp: new Date().toISOString(),
    }, 500);
  }
}

/**
 * Get AI Search ingestion status
 */
export async function getIngestionStatus(c: Context<{ Bindings: Env }>) {
  try {
    // Get module counts
    const totalResult = await c.env.MODULES_DB.prepare(
      'SELECT COUNT(*) as total FROM modules'
    ).first();

    // Check if AI Search is configured
    const aiSearchConfigured = !!(c.env.AI && c.env.AI_SEARCH);
    const aiGatewayConfigured = !!c.env.AI_GATEWAY;

    return c.json({
      status: 'ready',
      ai_search: {
        configured: aiSearchConfigured,
        index_name: aiSearchConfigured ? 'nixos-modules-search' : null,
      },
      ai_gateway: {
        configured: aiGatewayConfigured,
        gateway_id: aiGatewayConfigured ? c.env.AI_GATEWAY.id : null,
      },
      modules: {
        total: totalResult?.total || 0,
      },
      features: {
        keyword_search: true, // Always available via FTS5
        semantic_search: aiSearchConfigured,
        hybrid_search: aiSearchConfigured,
        ai_responses: aiSearchConfigured,
        query_rewriting: aiSearchConfigured && aiGatewayConfigured,
        automatic_chunking: aiSearchConfigured,
        model_caching: aiGatewayConfigured,
      },
      timestamp: new Date().toISOString(),
    });

  } catch (error) {
    console.error('Status check error:', error);

    return c.json({
      error: 'Status check failed',
      message: error instanceof Error ? error.message : String(error),
      timestamp: new Date().toISOString(),
    }, 500);
  }
}