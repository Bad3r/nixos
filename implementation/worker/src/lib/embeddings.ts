/**
 * Embeddings generation library for semantic search
 * Uses Workers AI with @cf/baai/bge-base-en-v1.5 model (768 dimensions)
 */

import type { Ai } from '@cloudflare/workers-types';

/**
 * Generate text blob for embedding from module data
 * Combines all searchable text into single string
 */
export function createTextBlob(module: {
  name: string;
  description?: string;
  namespace: string;
  options?: Array<{ name: string; description?: string }>;
}): string {
  const parts = [
    `Module: ${module.name}`,
    `Namespace: ${module.namespace}`,
    module.description ? `Description: ${module.description}` : '',
  ];

  // Add option information for richer context
  if (module.options && module.options.length > 0) {
    const optionTexts = module.options.map(opt =>
      `Option ${opt.name}${opt.description ? ': ' + opt.description : ''}`
    );
    parts.push('Options: ' + optionTexts.join('; '));
  }

  return parts.filter(Boolean).join('. ');
}

/**
 * Generate embedding vector using Workers AI
 * @param ai Workers AI binding
 * @param text Text to embed
 * @returns 768-dimension embedding vector
 */
export async function generateEmbedding(
  ai: Ai,
  text: string
): Promise<number[]> {
  const response = await ai.run(
    '@cf/baai/bge-base-en-v1.5',
    { text: [text] }
  ) as { shape: number[]; data: number[][] };

  // Workers AI returns shape: { shape: [1, 768], data: [[...768 numbers]] }
  if (!response.data || !response.data[0]) {
    throw new Error('Failed to generate embedding');
  }

  return response.data[0];
}
