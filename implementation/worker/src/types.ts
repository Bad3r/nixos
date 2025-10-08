/**
 * Type definitions for the NixOS Module Documentation API
 * Simplified for MVP implementation
 */

import type { D1Database, KVNamespace, R2Bucket, AnalyticsEngineDataset, Ai } from '@cloudflare/workers-types';

/**
 * Module types supported by the system
 */
export enum ModuleType {
  NIXOS = 'nixos',
  HOME_MANAGER = 'home-manager',
  FLAKE = 'flake'
}

/**
 * AI Gateway binding interface
 */
export interface AIGateway {
  id: string;
  // Add methods as needed for AI Gateway operations
}

/**
 * AI Search binding interface for automatic document processing
 */
export interface AISearch {
  index_name: string;
  aiSearch(params: AISearchParams): Promise<AISearchResponse>;
  search(params: SearchParams): Promise<SearchResponse>;
  ingest(documents: Document[]): Promise<IngestResponse>;
}

/**
 * AI Search parameters
 */
export interface AISearchParams {
  query: string;
  model?: string;
  rewrite_query?: boolean;
  max_num_results?: number;
  ranking_options?: {
    score_threshold?: number;
  };
  stream?: boolean;
}

/**
 * Search parameters for vector-only search
 */
export interface SearchParams {
  query: string;
  max_num_results?: number;
  ranking_options?: {
    score_threshold?: number;
  };
}

/**
 * AI Search response
 */
export interface AISearchResponse {
  response: string;
  sources: Array<{
    id: string;
    score: number;
    content: string;
    metadata?: Record<string, any>;
  }>;
  model_used?: string;
  query_rewritten?: string;
}

/**
 * Search response
 */
export interface SearchResponse {
  matches: Array<{
    id: string;
    score: number;
    content: string;
    metadata?: Record<string, any>;
  }>;
}

/**
 * Document for ingestion
 */
export interface Document {
  id: string;
  content: string;
  metadata?: Record<string, any>;
}

/**
 * Ingest response
 */
export interface IngestResponse {
  success: boolean;
  documents_processed: number;
  errors?: string[];
}

/**
 * Environment bindings for the Worker
 */
export interface Env {
  // D1 Database for module data
  MODULES_DB: D1Database;

  // KV for caching
  CACHE: KVNamespace;

  // R2 for document storage
  DOCUMENTS: R2Bucket;

  // Workers AI with AI Gateway integration
  AI: Ai;

  // AI Gateway for caching and model flexibility
  AI_GATEWAY?: AIGateway;

  // AI Search for automatic document processing
  AI_SEARCH?: AISearch;

  // Analytics (optional)
  ANALYTICS?: AnalyticsEngineDataset;

  // Static assets binding
  ASSETS?: Fetcher;

  // Environment variables
  ENVIRONMENT: string;
  CACHE_TTL: string;
  MAX_BATCH_SIZE: string;
  ENABLE_DEBUG: string;
  API_VERSION: string;

  // Secrets
  API_KEY: string;
  AI_GATEWAY_TOKEN: string; // Authentication token for AI Gateway
}

/**
 * Module data structure
 */
export interface Module {
  id?: number;
  path: string;
  name: string;
  namespace: string;
  description?: string;
  examples?: string[]; // JSON array stored as string in DB
  metadata?: Record<string, any>; // JSON object stored as string in DB
  created_at?: string;
  updated_at?: string;
}

/**
 * Module option structure
 */
export interface ModuleOption {
  id?: number;
  module_id: number;
  name: string;
  type: string;
  default_value?: any; // JSON stored as string in DB
  description?: string;
  example?: any; // JSON stored as string in DB
  read_only: boolean;
  internal: boolean;
}

/**
 * Module dependency structure
 */
export interface ModuleDependency {
  id?: number;
  module_id: number;
  depends_on_path: string;
  dependency_type: string;
}

/**
 * Host usage tracking
 */
export interface HostUsage {
  id?: number;
  hostname_hash: string; // SHA256 hash for privacy
  module_path: string;
  first_seen: string;
  last_seen: string;
}

/**
 * API Response types
 */
export interface ApiResponse<T = any> {
  data?: T;
  error?: string;
  pagination?: {
    total: number;
    limit: number;
    offset: number;
  };
  timestamp: string;
}

export interface ModuleWithOptions extends Module {
  options: ModuleOption[];
  dependencies: ModuleDependency[];
  usage_count?: number;
}

export interface SearchResult {
  query: string;
  results: Array<Module & { snippet?: string }>;
  count: number;
}

export interface Stats {
  total_modules: number;
  total_hosts: number;
  total_options: number;
  most_used_modules: Array<{
    path: string;
    name: string;
    namespace: string;
    usage_count: number;
  }>;
  namespaces: Array<{
    namespace: string;
    module_count: number;
  }>;
}

/**
 * Request validation schemas (for Zod)
 */
export interface ListModulesQuery {
  namespace?: string;
  limit?: number;
  offset?: number;
  sort?: 'name' | 'namespace' | 'usage' | 'updated';
}

export interface SearchModulesQuery {
  q: string;
  limit?: number;
  offset?: number;
  mode?: 'keyword' | 'semantic' | 'hybrid';
}

export interface BatchUpdateRequest {
  modules: Module[];
}

/**
 * Cache key helpers
 */
export const CacheKeys = {
  module: (namespace: string, name: string) => `module:${namespace}:${name}`,
  moduleList: (params: string) => `modules:list:${params}`,
  search: (query: string) => `search:${query}`,
  stats: () => 'stats:global',
  hostModules: (hostname: string) => `host:${hostname}:modules`,
} as const;

/**
 * Cache TTL values (in seconds)
 */
export const CacheTTL = {
  module: 300, // 5 minutes
  moduleList: 60, // 1 minute
  search: 120, // 2 minutes
  stats: 600, // 10 minutes
  hostModules: 300, // 5 minutes
} as const;