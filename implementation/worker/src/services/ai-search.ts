/**
 * AI Search Service
 * Handles document ingestion, hybrid search, and AI-powered responses
 * Replaces the custom embedding pipeline with Cloudflare AI Search
 */

import type { Env, Module, ModuleWithOptions } from '../types';

/**
 * AI Search configuration
 */
export const AI_SEARCH_CONFIG = {
  // Model for generating responses (can be overridden per request)
  DEFAULT_GENERATION_MODEL: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',

  // Model for embeddings (handled automatically by AI Search)
  EMBEDDING_MODEL: '@cf/baai/bge-base-en-v1.5',

  // Search configuration
  MAX_SEARCH_RESULTS: 10,
  DEFAULT_SCORE_THRESHOLD: 0.5,

  // Query rewriting for better retrieval
  ENABLE_QUERY_REWRITE: true,

  // Chunk configuration for document processing
  CHUNK_SIZE: 1000, // characters per chunk
  CHUNK_OVERLAP: 200, // overlap between chunks
};

/**
 * Document preparation for AI Search ingestion
 */
export function prepareDocumentForIngestion(module: ModuleWithOptions): {
  id: string;
  content: string;
  metadata: Record<string, any>;
} {
  // Create comprehensive text content for the module
  const contentParts = [
    `Module: ${module.name}`,
    `Namespace: ${module.namespace}`,
    module.description ? `Description: ${module.description}` : '',
    '',
    'Configuration Path:',
    module.path,
    '',
  ];

  // Add options information
  if (module.options && module.options.length > 0) {
    contentParts.push('Options:');
    module.options.forEach(opt => {
      const optionText = [
        `- ${opt.name} (${opt.type})`,
        opt.description ? `  ${opt.description}` : '',
        opt.default_value ? `  Default: ${JSON.stringify(opt.default_value)}` : '',
        opt.example ? `  Example: ${JSON.stringify(opt.example)}` : '',
      ].filter(Boolean).join('\n');
      contentParts.push(optionText);
    });
    contentParts.push('');
  }

  // Add dependencies information
  if (module.dependencies && module.dependencies.length > 0) {
    contentParts.push('Dependencies:');
    module.dependencies.forEach(dep => {
      contentParts.push(`- ${dep.depends_on_path} (${dep.dependency_type})`);
    });
    contentParts.push('');
  }

  // Add examples if available
  if (module.examples && module.examples.length > 0) {
    contentParts.push('Examples:');
    module.examples.forEach((example, idx) => {
      contentParts.push(`Example ${idx + 1}:`);
      contentParts.push(example);
      contentParts.push('');
    });
  }

  // Add usage statistics
  if (module.usage_count) {
    contentParts.push(`Usage: Used by ${module.usage_count} configurations`);
  }

  return {
    id: module.path, // Use module path as unique ID
    content: contentParts.filter(Boolean).join('\n'),
    metadata: {
      name: module.name,
      namespace: module.namespace,
      type: 'nixos-module',
      has_options: module.options?.length > 0,
      option_count: module.options?.length || 0,
      dependency_count: module.dependencies?.length || 0,
      usage_count: module.usage_count || 0,
      created_at: module.created_at,
      updated_at: module.updated_at,
    },
  };
}

/**
 * Batch ingest modules into AI Search
 */
export async function ingestModules(
  env: Env,
  modules: ModuleWithOptions[]
): Promise<{
  success: boolean;
  processed: number;
  errors: string[];
}> {
  if (!env.AI || !env.AI_SEARCH) {
    return {
      success: false,
      processed: 0,
      errors: ['AI Search is not configured'],
    };
  }

  const errors: string[] = [];
  let processed = 0;

  try {
    // Prepare documents for ingestion
    const documents = modules.map(module => prepareDocumentForIngestion(module));

    // Use AI Search's automatic ingestion with authenticated AI Gateway if available
    const gatewayConfig = env.AI_GATEWAY ? {
      gateway: {
        id: env.AI_GATEWAY.id,
        headers: {
          'cf-aig-authorization': `Bearer ${env.AI_GATEWAY_TOKEN}`
        }
      }
    } : {};

    // AI Search handles chunking, embedding generation, and vector storage automatically
    const response = await env.AI.autorag('nixos-modules-search').ingest({
      documents,
      ...gatewayConfig,
    });

    processed = documents.length;

    if (!response.success) {
      errors.push('Ingestion failed: ' + (response.error || 'Unknown error'));
    }

  } catch (error) {
    console.error('AI Search ingestion error:', error);
    errors.push(`Ingestion error: ${error instanceof Error ? error.message : String(error)}`);
  }

  return {
    success: errors.length === 0,
    processed,
    errors,
  };
}

/**
 * Perform hybrid search using AI Search
 */
export async function performHybridSearch(
  env: Env,
  query: string,
  options: {
    limit?: number;
    mode?: 'keyword' | 'semantic' | 'hybrid' | 'ai';
    generateResponse?: boolean;
    model?: string;
  } = {}
): Promise<{
  query: string;
  results: Array<{
    id: string;
    score: number;
    content: string;
    metadata?: Record<string, any>;
    snippet?: string;
  }>;
  aiResponse?: string;
  queryRewritten?: string;
  mode: string;
}> {
  if (!env.AI || !env.AI_SEARCH) {
    throw new Error('AI Search is not configured');
  }

  const limit = options.limit || AI_SEARCH_CONFIG.MAX_SEARCH_RESULTS;
  const mode = options.mode || 'hybrid';
  const generateResponse = options.generateResponse ?? (mode === 'ai');

  try {
    // Configure authenticated AI Gateway if available for caching and fallback
    const gatewayConfig = env.AI_GATEWAY ? {
      gateway: {
        id: env.AI_GATEWAY.id,
        headers: {
          'cf-aig-authorization': `Bearer ${env.AI_GATEWAY_TOKEN}`
        }
      }
    } : {};

    if (generateResponse || mode === 'ai') {
      // Use AI Search for response generation with context
      const response = await env.AI.autorag('nixos-modules-search').aiSearch({
        query,
        model: options.model || AI_SEARCH_CONFIG.DEFAULT_GENERATION_MODEL,
        rewrite_query: AI_SEARCH_CONFIG.ENABLE_QUERY_REWRITE,
        max_num_results: limit,
        ranking_options: {
          score_threshold: AI_SEARCH_CONFIG.DEFAULT_SCORE_THRESHOLD,
        },
        stream: false,
        ...gatewayConfig,
      });

      return {
        query,
        results: response.sources.map(source => ({
          id: source.id,
          score: source.score,
          content: source.content,
          metadata: source.metadata,
          snippet: createSnippet(source.content, query),
        })),
        aiResponse: response.response,
        queryRewritten: response.query_rewritten,
        mode: 'ai',
      };
    } else {
      // Use vector search without response generation
      const response = await env.AI.autorag('nixos-modules-search').search({
        query,
        max_num_results: limit,
        ranking_options: {
          score_threshold: AI_SEARCH_CONFIG.DEFAULT_SCORE_THRESHOLD,
        },
        ...gatewayConfig,
      });

      return {
        query,
        results: response.matches.map(match => ({
          id: match.id,
          score: match.score,
          content: match.content,
          metadata: match.metadata,
          snippet: createSnippet(match.content, query),
        })),
        mode: mode === 'keyword' ? 'keyword' : 'hybrid',
      };
    }
  } catch (error) {
    console.error('AI Search error:', error);
    throw new Error(`Search failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * Create a snippet from content highlighting query terms
 */
function createSnippet(content: string, query: string, maxLength: number = 200): string {
  const queryTerms = query.toLowerCase().split(/\s+/);
  const lines = content.split('\n');

  // Find the most relevant line containing query terms
  let bestLine = '';
  let bestScore = 0;

  for (const line of lines) {
    const lineLower = line.toLowerCase();
    let score = 0;

    for (const term of queryTerms) {
      if (lineLower.includes(term)) {
        score++;
      }
    }

    if (score > bestScore) {
      bestScore = score;
      bestLine = line;
    }
  }

  if (!bestLine) {
    // No matching line found, return first non-empty line
    bestLine = lines.find(l => l.trim().length > 0) || content.substring(0, maxLength);
  }

  // Truncate if necessary
  if (bestLine.length > maxLength) {
    bestLine = bestLine.substring(0, maxLength) + '...';
  }

  // Highlight query terms in the snippet
  let snippet = bestLine;
  for (const term of queryTerms) {
    const regex = new RegExp(`(${term})`, 'gi');
    snippet = snippet.replace(regex, '<mark>$1</mark>');
  }

  return snippet;
}

/**
 * Clear AI Search index (for reindexing)
 */
export async function clearSearchIndex(env: Env): Promise<void> {
  // AI Search doesn't provide a direct clear method
  // Reindexing with new documents will replace old ones
  console.log('AI Search index clear requested - will be cleared on next full reindex');
}

/**
 * Get search analytics
 */
export function trackSearchAnalytics(
  env: Env,
  query: string,
  resultCount: number,
  mode: string
): void {
  if (env.ANALYTICS) {
    try {
      env.ANALYTICS.writeDataPoint({
        indexes: ['ai_search', mode],
        blobs: [query.toLowerCase()],
        doubles: [resultCount, Date.now()],
      });
    } catch (error) {
      console.warn('Analytics write error:', error);
    }
  }
}