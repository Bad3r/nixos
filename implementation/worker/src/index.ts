/**
 * NixOS Module Documentation API Worker - Simplified MVP
 * REST API with D1 database, KV caching, and static frontend
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { Env } from './types';

// API route handlers
import { listModules } from './api/handlers/modules/list';
import { getModule } from './api/handlers/modules/get';
import { searchModules } from './api/handlers/modules/search';
import { batchUpdateModules } from './api/handlers/modules/batch-update';
import { getStats } from './api/handlers/stats';

const app = new Hono<{ Bindings: Env }>();

// Global middleware
app.use('*', cors({
  origin: (origin) => {
    // Allow requests from the same origin or configured domains
    const allowedOrigins = [
      'https://nixos-modules.org',
      'https://staging.nixos-modules.org',
    ];

    // In development, allow localhost
    if (process.env.ENVIRONMENT === 'development') {
      if (origin?.includes('localhost') || origin?.includes('127.0.0.1')) {
        return origin;
      }
    }

    // Check allowed origins
    if (allowedOrigins.includes(origin || '')) {
      return origin || '';
    }

    // Reject all other origins
    return false;
  },
  allowMethods: ['GET', 'POST', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'X-API-Key'],
  maxAge: 86400,
}));

// Error handling
app.onError((err, c) => {
  console.error('Error:', err);
  return c.json({
    error: err.message || 'Internal Server Error',
    timestamp: new Date().toISOString(),
  }, 500);
});

// Health check
app.get('/health', (c) => {
  return c.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: c.env.ENVIRONMENT || 'development',
    version: '1.0.0',
  });
});

// Public API routes (no auth required for MVP)
app.get('/api/modules', listModules);
app.get('/api/modules/:namespace/:name', getModule);
app.get('/api/modules/search', searchModules);
app.get('/api/stats', getStats);

// Helper function for timing-safe string comparison
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  if (!a || !b) return false;
  if (a.length !== b.length) return false;

  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);

  // Use Web Crypto API for constant-time comparison
  const aKey = await crypto.subtle.importKey(
    'raw',
    aBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const bKey = await crypto.subtle.importKey(
    'raw',
    bBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const aSignature = await crypto.subtle.sign('HMAC', aKey, new Uint8Array(1));
  const bSignature = await crypto.subtle.sign('HMAC', bKey, new Uint8Array(1));

  const aHash = new Uint8Array(aSignature);
  const bHash = new Uint8Array(bSignature);

  let result = 0;
  for (let i = 0; i < aHash.length; i++) {
    result |= aHash[i] ^ bHash[i];
  }

  return result === 0;
}

// Protected API routes (timing-safe API key auth)
app.post('/api/modules/batch', async (c, next) => {
  const apiKey = c.req.header('X-API-Key');
  const validKey = c.env.API_KEY;

  if (!apiKey || !validKey || !(await timingSafeEqual(apiKey, validKey))) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  return next();
}, batchUpdateModules);

// Root redirect to docs
app.get('/', (c) => {
  return c.redirect('/docs');
});

// Simple docs page
app.get('/docs', (c) => {
  return c.json({
    name: 'NixOS Module Documentation API',
    version: '1.0.0',
    environment: c.env.ENVIRONMENT || 'development',
    endpoints: {
      health: {
        method: 'GET',
        path: '/health',
        description: 'Health check endpoint',
      },
      stats: {
        method: 'GET',
        path: '/api/stats',
        description: 'Get statistics about modules',
      },
      listModules: {
        method: 'GET',
        path: '/api/modules',
        description: 'List all modules',
        params: {
          namespace: 'Filter by namespace (optional)',
          limit: 'Limit results (default: 50)',
          offset: 'Pagination offset (default: 0)',
        },
      },
      getModule: {
        method: 'GET',
        path: '/api/modules/:namespace/:name',
        description: 'Get a specific module',
      },
      searchModules: {
        method: 'GET',
        path: '/api/modules/search',
        description: 'Search modules by name or description',
        params: {
          q: 'Search query (required)',
        },
      },
      batchUpdate: {
        method: 'POST',
        path: '/api/modules/batch',
        description: 'Batch update modules (requires X-API-Key)',
      },
    },
    links: {
      stats: '/api/stats',
      modules: '/api/modules',
      health: '/health',
    },
  });
});

// 404 handler for API routes
app.all('/api/*', (c) => {
  return c.json({
    error: 'Not Found',
    path: c.req.path,
    timestamp: new Date().toISOString(),
  }, 404);
});

// Catch-all 404 handler
app.notFound((c) => {
  return c.json({
    error: 'Not Found',
    path: c.req.path,
    message: 'This endpoint does not exist. Visit /docs for API documentation.',
    timestamp: new Date().toISOString(),
  }, 404);
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // Route all requests through Hono (handles /, /api/*, /health, 404s, etc.)
    return app.fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;