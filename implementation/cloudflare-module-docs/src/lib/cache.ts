/**
 * Advanced Cache Management System with Versioning and Invalidation
 * Features:
 * - Content versioning
 * - Pattern-based invalidation
 * - Cache warming
 * - Multi-tier caching (KV + Edge)
 * - Distributed invalidation via Durable Objects
 */

import { z } from "zod";
import { DurableObject } from "cloudflare:workers";

// Cache configuration
export interface CacheConfig {
  // KV namespaces
  MODULE_CACHE: KVNamespace;
  VERSION_CACHE: KVNamespace;

  // Durable Objects
  CACHE_INVALIDATOR: DurableObjectNamespace;

  // Configuration
  DEFAULT_TTL: number;
  MAX_TTL: number;
  STALE_WHILE_REVALIDATE: number;
  VERSION_KEY_PREFIX: string;
}

// Cache entry metadata
interface CacheMetadata {
  version: string;
  created: number;
  expires: number;
  etag: string;
  contentType: string;
  compressed: boolean;
  tags: string[];
  dependencies: string[];
  staleWhileRevalidate?: number;
  staleIfError?: number;
}

// Cache key types
export enum CacheKeyType {
  MODULE = "module",
  SEARCH = "search",
  LIST = "list",
  STATS = "stats",
  DEPENDENCY = "dep",
  HOST = "host",
}

// Cache invalidation patterns
export enum InvalidationPattern {
  EXACT = "exact",
  PREFIX = "prefix",
  TAG = "tag",
  DEPENDENCY = "dependency",
  ALL = "all",
}

/**
 * Main cache manager class
 */
export class CacheManager {
  private currentVersion: string;

  constructor(private config: CacheConfig) {
    // Initialize with timestamp-based version
    this.currentVersion = Date.now().toString(36);
  }

  /**
   * Get an item from cache with version checking
   */
  async get<T>(
    key: string,
    options: {
      type?: CacheKeyType;
      acceptStale?: boolean;
      validateFn?: (value: T) => boolean;
    } = {},
  ): Promise<T | null> {
    const versionedKey = this.getVersionedKey(key, options.type);

    try {
      // Try to get from KV with metadata
      const { value, metadata } =
        await this.config.MODULE_CACHE.getWithMetadata<CacheMetadata>(
          versionedKey,
          { type: "json" },
        );

      if (!value || !metadata) {
        return null;
      }

      // Check if expired
      const now = Date.now();
      if (metadata.expires < now) {
        // Check if we can serve stale content
        if (options.acceptStale && metadata.staleWhileRevalidate) {
          const staleDeadline =
            metadata.expires + metadata.staleWhileRevalidate * 1000;
          if (now < staleDeadline) {
            // Trigger background revalidation
            this.triggerRevalidation(key, options.type);
            return value as T;
          }
        }
        // Expired and can't serve stale
        await this.delete(key, options.type);
        return null;
      }

      // Validate if function provided
      if (options.validateFn && !options.validateFn(value as T)) {
        await this.delete(key, options.type);
        return null;
      }

      // Decompress if needed
      if (metadata.compressed) {
        const decompressed = await this.decompress(value as any);
        return JSON.parse(decompressed) as T;
      }

      return value as T;
    } catch (error) {
      console.error(`Cache get error for ${key}:`, error);
      return null;
    }
  }

  /**
   * Set an item in cache with versioning and metadata
   */
  async set<T>(
    key: string,
    value: T,
    options: {
      type?: CacheKeyType;
      ttl?: number;
      tags?: string[];
      dependencies?: string[];
      compress?: boolean;
      staleWhileRevalidate?: number;
      staleIfError?: number;
    } = {},
  ): Promise<void> {
    const versionedKey = this.getVersionedKey(key, options.type);
    const ttl = Math.min(
      options.ttl || this.config.DEFAULT_TTL,
      this.config.MAX_TTL,
    );

    try {
      // Prepare value
      let storedValue: any = value;
      let compressed = false;

      // Compress if requested and value is large enough
      if (options.compress) {
        const serialized = JSON.stringify(value);
        if (serialized.length > 1024) {
          storedValue = await this.compress(serialized);
          compressed = true;
        }
      }

      // Create metadata
      const metadata: CacheMetadata = {
        version: this.currentVersion,
        created: Date.now(),
        expires: Date.now() + ttl * 1000,
        etag: await this.generateETag(value),
        contentType: "application/json",
        compressed,
        tags: options.tags || [],
        dependencies: options.dependencies || [],
        staleWhileRevalidate: options.staleWhileRevalidate,
        staleIfError: options.staleIfError,
      };

      // Store in KV with metadata
      await this.config.MODULE_CACHE.put(
        versionedKey,
        compressed ? storedValue : JSON.stringify(storedValue),
        {
          expirationTtl: ttl,
          metadata,
        },
      );

      // Store version mapping
      await this.storeVersionMapping(key, versionedKey, options.type);

      // Register tags for invalidation
      if (options.tags?.length) {
        await this.registerTags(versionedKey, options.tags);
      }

      // Register dependencies
      if (options.dependencies?.length) {
        await this.registerDependencies(versionedKey, options.dependencies);
      }
    } catch (error) {
      console.error(`Cache set error for ${key}:`, error);
      throw error;
    }
  }

  /**
   * Delete an item from cache
   */
  async delete(key: string, type?: CacheKeyType): Promise<void> {
    const versionedKey = this.getVersionedKey(key, type);
    await this.config.MODULE_CACHE.delete(versionedKey);
    await this.removeVersionMapping(key, type);
  }

  /**
   * Invalidate cache by pattern
   */
  async invalidate(
    pattern: string,
    type: InvalidationPattern,
    options: {
      async?: boolean;
      broadcast?: boolean;
    } = {},
  ): Promise<number> {
    const invalidator = this.getInvalidator();

    if (options.broadcast) {
      // Use Durable Object for coordinated invalidation
      return await invalidator.invalidate(pattern, type);
    }

    let count = 0;

    switch (type) {
      case InvalidationPattern.EXACT:
        await this.delete(pattern);
        count = 1;
        break;

      case InvalidationPattern.PREFIX:
        count = await this.invalidateByPrefix(pattern);
        break;

      case InvalidationPattern.TAG:
        count = await this.invalidateByTag(pattern);
        break;

      case InvalidationPattern.DEPENDENCY:
        count = await this.invalidateByDependency(pattern);
        break;

      case InvalidationPattern.ALL:
        count = await this.invalidateAll();
        break;
    }

    return count;
  }

  /**
   * Warm the cache with frequently accessed data
   */
  async warmCache(
    items: Array<{
      key: string;
      generator: () => Promise<any>;
      options?: any;
    }>,
  ): Promise<void> {
    const warmingPromises = items.map(async (item) => {
      try {
        // Check if already cached
        const cached = await this.get(item.key, item.options);
        if (!cached) {
          // Generate and cache
          const value = await item.generator();
          await this.set(item.key, value, item.options);
        }
      } catch (error) {
        console.error(`Cache warming failed for ${item.key}:`, error);
      }
    });

    await Promise.allSettled(warmingPromises);
  }

  /**
   * Get cache statistics
   */
  async getStats(): Promise<{
    size: number;
    hitRate: number;
    missRate: number;
    avgLatency: number;
    topKeys: string[];
  }> {
    // This would typically integrate with Analytics Engine
    // For now, return mock stats
    return {
      size: 0,
      hitRate: 0,
      missRate: 0,
      avgLatency: 0,
      topKeys: [],
    };
  }

  /**
   * Invalidate by prefix pattern
   */
  private async invalidateByPrefix(prefix: string): Promise<number> {
    let count = 0;
    let cursor: string | undefined;

    do {
      const list = await this.config.MODULE_CACHE.list({
        prefix: `${this.currentVersion}:${prefix}`,
        cursor,
        limit: 1000,
      });

      const deletePromises = list.keys.map((key) =>
        this.config.MODULE_CACHE.delete(key.name),
      );

      await Promise.all(deletePromises);
      count += list.keys.length;
      cursor = list.list_complete ? undefined : list.cursor;
    } while (cursor);

    return count;
  }

  /**
   * Invalidate by tag
   */
  private async invalidateByTag(tag: string): Promise<number> {
    const tagKey = `tag:${tag}`;
    const keys = await this.config.VERSION_CACHE.get<string[]>(tagKey, "json");

    if (!keys || !keys.length) {
      return 0;
    }

    const deletePromises = keys.map((key) =>
      this.config.MODULE_CACHE.delete(key),
    );

    await Promise.all(deletePromises);
    await this.config.VERSION_CACHE.delete(tagKey);

    return keys.length;
  }

  /**
   * Invalidate by dependency
   */
  private async invalidateByDependency(dependency: string): Promise<number> {
    const depKey = `dep:${dependency}`;
    const keys = await this.config.VERSION_CACHE.get<string[]>(depKey, "json");

    if (!keys || !keys.length) {
      return 0;
    }

    const deletePromises = keys.map((key) =>
      this.config.MODULE_CACHE.delete(key),
    );

    await Promise.all(deletePromises);
    await this.config.VERSION_CACHE.delete(depKey);

    return keys.length;
  }

  /**
   * Invalidate all cache entries
   */
  private async invalidateAll(): Promise<number> {
    // Increment version to invalidate all existing keys
    this.currentVersion = Date.now().toString(36);
    await this.config.VERSION_CACHE.put("current_version", this.currentVersion);

    // Count approximate entries (KV list is eventually consistent)
    const list = await this.config.MODULE_CACHE.list({ limit: 1 });
    return list.keys.length > 0 ? 1000 : 0; // Approximate
  }

  /**
   * Register tags for a cache key
   */
  private async registerTags(key: string, tags: string[]): Promise<void> {
    const tagPromises = tags.map(async (tag) => {
      const tagKey = `tag:${tag}`;
      const existing =
        (await this.config.VERSION_CACHE.get<string[]>(tagKey, "json")) || [];
      existing.push(key);
      await this.config.VERSION_CACHE.put(tagKey, JSON.stringify(existing));
    });

    await Promise.all(tagPromises);
  }

  /**
   * Register dependencies for a cache key
   */
  private async registerDependencies(
    key: string,
    dependencies: string[],
  ): Promise<void> {
    const depPromises = dependencies.map(async (dep) => {
      const depKey = `dep:${dep}`;
      const existing =
        (await this.config.VERSION_CACHE.get<string[]>(depKey, "json")) || [];
      existing.push(key);
      await this.config.VERSION_CACHE.put(depKey, JSON.stringify(existing));
    });

    await Promise.all(depPromises);
  }

  /**
   * Get versioned cache key
   */
  private getVersionedKey(key: string, type?: CacheKeyType): string {
    const prefix = type ? `${type}:` : "";
    return `${this.currentVersion}:${prefix}${key}`;
  }

  /**
   * Store version mapping
   */
  private async storeVersionMapping(
    key: string,
    versionedKey: string,
    type?: CacheKeyType,
  ): Promise<void> {
    const mappingKey = `map:${type || "default"}:${key}`;
    await this.config.VERSION_CACHE.put(mappingKey, versionedKey);
  }

  /**
   * Remove version mapping
   */
  private async removeVersionMapping(
    key: string,
    type?: CacheKeyType,
  ): Promise<void> {
    const mappingKey = `map:${type || "default"}:${key}`;
    await this.config.VERSION_CACHE.delete(mappingKey);
  }

  /**
   * Trigger background revalidation
   */
  private triggerRevalidation(key: string, type?: CacheKeyType): void {
    // This would trigger a background fetch to refresh the cache
    // Implementation depends on the specific use case
    console.log(`Triggering revalidation for ${key}`);
  }

  /**
   * Generate ETag for cache entry
   */
  private async generateETag(value: any): Promise<string> {
    const text = JSON.stringify(value);
    const encoder = new TextEncoder();
    const data = encoder.encode(text);
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")
      .substring(0, 16);
  }

  /**
   * Compress data
   */
  private async compress(data: string): Promise<ArrayBuffer> {
    const encoder = new TextEncoder();
    const stream = new CompressionStream("gzip");
    const writer = stream.writable.getWriter();
    writer.write(encoder.encode(data));
    writer.close();

    const chunks: Uint8Array[] = [];
    const reader = stream.readable.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    const totalLength = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    return result.buffer;
  }

  /**
   * Decompress data
   */
  private async decompress(data: ArrayBuffer): Promise<string> {
    const stream = new DecompressionStream("gzip");
    const writer = stream.writable.getWriter();
    writer.write(new Uint8Array(data));
    writer.close();

    const chunks: Uint8Array[] = [];
    const reader = stream.readable.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    const decoder = new TextDecoder();
    return chunks.map((chunk) => decoder.decode(chunk)).join("");
  }

  /**
   * Get cache invalidator Durable Object
   */
  private getInvalidator(): CacheInvalidatorInstance {
    const id = this.config.CACHE_INVALIDATOR.idFromName("global");
    return this.config.CACHE_INVALIDATOR.get(id) as any;
  }
}

/**
 * Durable Object for coordinating cache invalidation
 */
export class CacheInvalidator extends DurableObject {
  private subscribers: Set<WebSocket> = new Set();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // Handle WebSocket upgrade for real-time invalidation
    if (request.headers.get("Upgrade") === "websocket") {
      return this.handleWebSocket(request);
    }

    // Handle invalidation request
    if (url.pathname === "/invalidate" && request.method === "POST") {
      const { pattern, type } = await request.json<{
        pattern: string;
        type: InvalidationPattern;
      }>();

      const count = await this.broadcastInvalidation(pattern, type);
      return Response.json({ invalidated: count });
    }

    return new Response("Not Found", { status: 404 });
  }

  /**
   * Handle WebSocket connections for real-time invalidation
   */
  private handleWebSocket(request: Request): Response {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server);
    this.subscribers.add(server);

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  /**
   * WebSocket message handler
   */
  async webSocketMessage(
    ws: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<void> {
    try {
      const data = JSON.parse(message as string);

      if (data.type === "invalidate") {
        await this.broadcastInvalidation(data.pattern, data.invalidationType);
      }
    } catch (error) {
      ws.send(JSON.stringify({ error: error.message }));
    }
  }

  /**
   * WebSocket close handler
   */
  async webSocketClose(ws: WebSocket): Promise<void> {
    this.subscribers.delete(ws);
  }

  /**
   * Broadcast invalidation to all subscribers
   */
  private async broadcastInvalidation(
    pattern: string,
    type: InvalidationPattern,
  ): Promise<number> {
    const message = JSON.stringify({
      type: "invalidation",
      pattern,
      invalidationType: type,
      timestamp: Date.now(),
    });

    let count = 0;
    for (const ws of this.subscribers) {
      try {
        ws.send(message);
        count++;
      } catch (error) {
        // Remove dead connections
        this.subscribers.delete(ws);
      }
    }

    return count;
  }

  /**
   * Perform actual invalidation
   */
  async invalidate(
    pattern: string,
    type: InvalidationPattern,
  ): Promise<number> {
    // Broadcast to all connected clients
    await this.broadcastInvalidation(pattern, type);

    // Return estimated count (actual invalidation happens on each Worker)
    return this.subscribers.size;
  }
}

// Type for Durable Object instance
interface CacheInvalidatorInstance {
  invalidate(pattern: string, type: InvalidationPattern): Promise<number>;
}

/**
 * Cache middleware for Hono
 */
export function cacheMiddleware(
  options: {
    keyGenerator?: (c: any) => string;
    ttl?: number;
    tags?: string[];
    condition?: (c: any) => boolean;
  } = {},
) {
  return async (c: any, next: any) => {
    // Check if caching should be applied
    if (options.condition && !options.condition(c)) {
      return await next();
    }

    // Generate cache key
    const key = options.keyGenerator
      ? options.keyGenerator(c)
      : `${c.req.method}:${c.req.url}`;

    // Try to get from cache
    const cacheManager = new CacheManager(c.env);
    const cached = await cacheManager.get(key, {
      type: CacheKeyType.MODULE,
      acceptStale: true,
    });

    if (cached) {
      // Cache hit
      c.header("X-Cache", "HIT");
      return c.json(cached);
    }

    // Cache miss - proceed with request
    await next();

    // Cache the response if successful
    if (c.res.status === 200) {
      const body = await c.res.json();
      await cacheManager.set(key, body, {
        type: CacheKeyType.MODULE,
        ttl: options.ttl,
        tags: options.tags,
        staleWhileRevalidate: 60,
      });
      c.header("X-Cache", "MISS");
    }
  };
}
