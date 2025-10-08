/**
 * AI Search Service
 * Handles query execution against Cloudflare AI Search via Workers AI bindings.
 */

import type { Env } from "../types";

export const AI_SEARCH_CONFIG = {
  DEFAULT_GENERATION_MODEL: "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
  MAX_SEARCH_RESULTS: 10,
  DEFAULT_SCORE_THRESHOLD: 0.5,
  ENABLE_QUERY_REWRITE: true,
};

type HybridSearchOptions = {
  limit?: number;
  mode?: "keyword" | "semantic" | "hybrid" | "ai";
  generateResponse?: boolean;
};

export async function performHybridSearch(
  env: Env,
  query: string,
  options: HybridSearchOptions = {},
): Promise<{
  query: string;
  results: Array<{
    id: string;
    score: number;
    content: string;
    metadata?: Record<string, unknown>;
    snippet?: string;
  }>;
  aiResponse?: string;
  queryRewritten?: string;
  mode: string;
}> {
  if (!env.AI) {
    throw new Error("AI Search is not configured");
  }

  const limit = options.limit ?? AI_SEARCH_CONFIG.MAX_SEARCH_RESULTS;
  const mode = options.mode ?? "hybrid";
  const generateResponse = options.generateResponse ?? mode === "ai";
  const autoragName = env.AI_AUTORAG_NAME ?? "nixos-modules-search";
  const baseRequest: AutoRagRequestShape = {
    query,
    rewrite_query: AI_SEARCH_CONFIG.ENABLE_QUERY_REWRITE,
    max_num_results: limit,
    ranking_options: {
      score_threshold: AI_SEARCH_CONFIG.DEFAULT_SCORE_THRESHOLD,
    },
  };

  const autorag = env.AI.autorag(autoragName);

  if (generateResponse || mode === "ai") {
    const response = (await autorag.aiSearch(baseRequest as any)) as unknown as {
      data: AutoRagItem[];
      response: string;
    };

    return {
      query,
      results: response.data.map((item) => mapSearchItem(item, query)),
      aiResponse: response.response,
      queryRewritten: undefined,
      mode: "ai",
    };
  }

  const response = (await autorag.search(baseRequest as any)) as unknown as {
    data: AutoRagItem[];
  };

  return {
    query,
    results: response.data.map((item) => mapSearchItem(item, query)),
    mode: mode === "keyword" ? "keyword" : "hybrid",
  };
}

type AutoRagItem = {
  file_id: string;
  filename: string;
  score: number;
  attributes: Record<string, string | number | boolean | null>;
  content: { type: string; text: string }[];
};

type AutoRagRequestShape = {
  query: string;
  rewrite_query?: boolean;
  max_num_results?: number;
  ranking_options?: {
    score_threshold?: number;
  };
};

function mapSearchItem(item: AutoRagItem, query: string) {
  const text = item.content.map((block) => block.text).join("\n\n");

  return {
    id: item.file_id,
    score: item.score,
    content: text,
    metadata: item.attributes,
    snippet: createSnippet(text, query),
  };
}

function createSnippet(
  content: string,
  query: string,
  maxLength: number = 200,
): string {
  const queryTerms = query.toLowerCase().split(/\s+/);
  const lines = content.split("\n");

  let bestLine = "";
  let bestScore = 0;

  for (const line of lines) {
    const lineLower = line.toLowerCase();
    let score = 0;

    for (const term of queryTerms) {
      if (lineLower.includes(term)) {
        score += 1;
      }
    }

    if (score > bestScore) {
      bestScore = score;
      bestLine = line;
    }
  }

  if (!bestLine) {
    bestLine =
      lines.find((l) => l.trim().length > 0) ??
      content.substring(0, Math.min(content.length, maxLength));
  }

  if (bestLine.length > maxLength) {
    bestLine = `${bestLine.substring(0, maxLength)}...`;
  }

  let snippet = bestLine;
  for (const term of queryTerms) {
    const regex = new RegExp(`(${term})`, "gi");
    snippet = snippet.replace(regex, "<mark>$1</mark>");
  }

  return snippet;
}

export function trackSearchAnalytics(
  env: Env,
  query: string,
  resultCount: number,
  mode: string,
): void {
  if (!env.ANALYTICS) {
    return;
  }

  try {
    env.ANALYTICS.writeDataPoint({
      indexes: ["search"],
      blobs: [query.toLowerCase(), mode],
      doubles: [resultCount, Date.now()],
    });
  } catch (error) {
    console.warn("Analytics write error:", error);
  }
}
