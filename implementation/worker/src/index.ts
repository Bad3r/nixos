/**
 * NixOS Module Documentation API Worker - Simplified MVP
 * REST API with D1 database, KV caching, and static frontend
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { compress } from 'hono/compress';
import type { Env } from './types';

// API route handlers
import { listModules } from './api/handlers/modules/list';
import { getModule } from './api/handlers/modules/get';
import { searchModules } from './api/handlers/modules/search';
import { batchUpdateModules } from './api/handlers/modules/batch-update';
import { getStats } from './api/handlers/stats';

const app = new Hono<{ Bindings: Env }>();

// Global middleware
app.use('*', compress());
app.use('*', cors({
  origin: '*', // Allow all origins for MVP, restrict in production
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

// Protected API routes (simple API key auth)
app.post('/api/modules/batch', async (c, next) => {
  const apiKey = c.req.header('X-API-Key');
  const validKey = c.env.API_KEY;

  if (!apiKey || apiKey !== validKey) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  return next();
}, batchUpdateModules);

// 404 handler for API routes
app.all('/api/*', (c) => {
  return c.json({
    error: 'Not Found',
    path: c.req.path,
    timestamp: new Date().toISOString(),
  }, 404);
});

// Root redirect to docs
app.get('/', (c) => {
  return c.redirect('/docs');
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Handle API and health check routes with Hono
    if (url.pathname.startsWith('/api/') || url.pathname === '/health') {
      return app.fetch(request, env, ctx);
    }

    // Serve static assets (frontend) for all other routes
    // This assumes ASSETS binding exists from wrangler.jsonc
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    // Fallback if no assets binding
    return new Response('Not Found', { status: 404 });
  },
} satisfies ExportedHandler<Env>;