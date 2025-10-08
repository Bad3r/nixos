/**
 * Zod validation schemas for all API endpoints
 * Comprehensive validation with security constraints
 */

import { z } from 'zod';
import { ModuleType } from '../types';

// Common patterns and constraints
const SAFE_STRING_PATTERN = /^[\w\s\-\.\/@]+$/;
const MODULE_NAME_PATTERN = /^[a-zA-Z][a-zA-Z0-9\-\.]*$/;
const NAMESPACE_PATTERN = /^[a-z][a-z0-9\-]*$/;

// Search query validation
export const searchQuerySchema = z.object({
  q: z.string()
    .min(2, 'Query must be at least 2 characters')
    .max(100, 'Query cannot exceed 100 characters')
    .regex(SAFE_STRING_PATTERN, 'Query contains invalid characters')
    .transform(q => q.trim()),
  namespace: z.string()
    .regex(NAMESPACE_PATTERN, 'Invalid namespace format')
    .optional(),
  type: z.nativeEnum(ModuleType).optional(),
  limit: z.coerce.number()
    .min(1, 'Limit must be at least 1')
    .max(100, 'Limit cannot exceed 100')
    .default(20),
  offset: z.coerce.number()
    .min(0, 'Offset cannot be negative')
    .default(0),
});

// Module schema for creation/update
export const moduleOptionSchema = z.object({
  name: z.string()
    .min(1, 'Option name is required')
    .max(200, 'Option name too long')
    .regex(SAFE_STRING_PATTERN, 'Invalid characters in option name'),
  type: z.string()
    .min(1, 'Type is required')
    .max(500, 'Type definition too long'),
  default: z.any().optional(),
  description: z.string()
    .max(5000, 'Description too long')
    .optional(),
  example: z.any().optional(),
  readOnly: z.boolean().optional(),
  visible: z.boolean().optional(),
  internal: z.boolean().optional(),
});

export const declarationSchema = z.object({
  file: z.string()
    .min(1, 'File path is required')
    .max(500, 'File path too long')
    .regex(/^[\w\-\.\/]+$/, 'Invalid file path'),
  line: z.number()
    .min(1)
    .max(999999)
    .optional(),
  column: z.number()
    .min(1)
    .max(999)
    .optional(),
  url: z.string()
    .url('Invalid URL format')
    .max(1000, 'URL too long')
    .optional(),
});

export const exampleSchema = z.object({
  title: z.string()
    .max(200, 'Title too long')
    .optional(),
  code: z.string()
    .min(1, 'Code is required')
    .max(10000, 'Code example too long'),
  description: z.string()
    .max(2000, 'Description too long')
    .optional(),
});

export const moduleMetadataSchema = z.object({
  maintainers: z.array(z.string().max(100))
    .max(20, 'Too many maintainers')
    .optional(),
  platforms: z.array(z.string().max(50))
    .max(10, 'Too many platforms')
    .optional(),
  license: z.string()
    .max(100, 'License string too long')
    .optional(),
  homepage: z.string()
    .url('Invalid homepage URL')
    .max(500, 'Homepage URL too long')
    .optional(),
  lastModified: z.string()
    .datetime()
    .optional(),
  hash: z.string()
    .regex(/^[a-f0-9]{64}$/, 'Invalid SHA256 hash')
    .optional(),
});

export const moduleSchema = z.object({
  name: z.string()
    .min(1, 'Module name is required')
    .max(200, 'Module name too long')
    .regex(MODULE_NAME_PATTERN, 'Invalid module name format'),
  namespace: z.string()
    .min(1, 'Namespace is required')
    .max(100, 'Namespace too long')
    .regex(NAMESPACE_PATTERN, 'Invalid namespace format'),
  description: z.string()
    .max(5000, 'Description too long')
    .optional(),
  type: z.nativeEnum(ModuleType),
  options: z.array(moduleOptionSchema)
    .max(1000, 'Too many options'),
  declarations: z.array(declarationSchema)
    .max(100, 'Too many declarations'),
  examples: z.array(exampleSchema)
    .max(20, 'Too many examples')
    .optional(),
  metadata: moduleMetadataSchema,
  searchVector: z.array(z.number())
    .length(1536, 'Invalid vector dimension')
    .optional(),
}).refine(
  (module) => {
    // Validate total size doesn't exceed reasonable limits
    const jsonSize = JSON.stringify(module).length;
    return jsonSize < 1000000; // 1MB limit per module
  },
  { message: 'Module data too large (exceeds 1MB)' }
);

// Batch update schema
export const batchUpdateSchema = z.object({
  modules: z.array(moduleSchema)
    .min(1, 'At least one module required')
    .max(50, 'Batch cannot exceed 50 modules')
    .refine(
      (modules) => {
        const jsonSize = JSON.stringify(modules).length;
        return jsonSize < 500000; // 500KB total batch limit
      },
      { message: 'Batch payload too large (exceeds 500KB)' }
    ),
  updateMode: z.enum(['merge', 'replace']).default('replace'),
  validateOnly: z.boolean().default(false),
});

// PR preview schema
export const prPreviewSchema = z.object({
  prNumber: z.string()
    .regex(/^\d+$/, 'Invalid PR number')
    .transform(pr => parseInt(pr, 10))
    .refine(pr => pr > 0 && pr < 1000000, 'PR number out of range'),
  modules: z.array(moduleSchema)
    .min(1, 'At least one module required')
    .max(100, 'Preview cannot exceed 100 modules'),
  branch: z.string()
    .max(100, 'Branch name too long')
    .regex(/^[a-zA-Z0-9\-\_\/]+$/, 'Invalid branch name')
    .optional(),
  sha: z.string()
    .regex(/^[a-f0-9]{40}$/, 'Invalid commit SHA')
    .optional(),
});

// Webhook payload schema
export const webhookPayloadSchema = z.object({
  event: z.enum(['push', 'pull_request', 'release']),
  repository: z.string()
    .max(200, 'Repository name too long'),
  ref: z.string()
    .max(200, 'Ref too long')
    .optional(),
  before: z.string()
    .regex(/^[a-f0-9]{40}$/, 'Invalid before SHA')
    .optional(),
  after: z.string()
    .regex(/^[a-f0-9]{40}$/, 'Invalid after SHA')
    .optional(),
  signature: z.string()
    .max(500, 'Signature too long')
    .optional(),
});

// Analytics event schema
export const analyticsEventSchema = z.object({
  type: z.enum(['search', 'view', 'update', 'error']),
  query: z.string()
    .max(200, 'Query too long')
    .optional(),
  moduleId: z.string()
    .max(200, 'Module ID too long')
    .optional(),
  duration: z.number()
    .min(0)
    .max(60000) // Max 1 minute
    .optional(),
  resultCount: z.number()
    .min(0)
    .max(10000)
    .optional(),
  error: z.string()
    .max(500, 'Error message too long')
    .optional(),
  timestamp: z.number()
    .min(0)
    .default(() => Date.now()),
});

// Authentication token schema
export const authTokenSchema = z.object({
  token: z.string()
    .min(1, 'Token is required')
    .max(1000, 'Token too long'),
  type: z.enum(['Bearer', 'API-Key']).default('Bearer'),
});

// Request ID schema for tracing
export const requestIdSchema = z.object({
  requestId: z.string()
    .uuid('Invalid request ID format')
    .optional(),
  traceId: z.string()
    .uuid('Invalid trace ID format')
    .optional(),
});

// Pagination schema
export const paginationSchema = z.object({
  page: z.coerce.number()
    .min(1, 'Page must be at least 1')
    .default(1),
  perPage: z.coerce.number()
    .min(1, 'Items per page must be at least 1')
    .max(100, 'Items per page cannot exceed 100')
    .default(20),
  sortBy: z.string()
    .max(50, 'Sort field name too long')
    .regex(/^[a-zA-Z_]+$/, 'Invalid sort field')
    .optional(),
  sortOrder: z.enum(['asc', 'desc']).default('asc'),
});

// Environment variable schema for validation
export const envSchema = z.object({
  ENVIRONMENT: z.enum(['development', 'staging', 'production']),
  JWT_SECRET: z.string().min(32, 'JWT secret too short'),
  API_TOKEN: z.string().min(32, 'API token too short'),
  CF_ACCESS_AUD: z.string().optional(),
  CF_ACCESS_TEAM_DOMAIN: z.string().optional(),
  CACHE_TTL: z.coerce.number().min(0).max(86400),
  MAX_BATCH_SIZE: z.coerce.number().min(1).max(100),
  ENABLE_DEBUG: z.coerce.boolean(),
});

// Export type inference helpers
export type SearchQuery = z.infer<typeof searchQuerySchema>;
export type Module = z.infer<typeof moduleSchema>;
export type BatchUpdate = z.infer<typeof batchUpdateSchema>;
export type PrPreview = z.infer<typeof prPreviewSchema>;
export type WebhookPayload = z.infer<typeof webhookPayloadSchema>;
export type AnalyticsEvent = z.infer<typeof analyticsEventSchema>;
export type Pagination = z.infer<typeof paginationSchema>;