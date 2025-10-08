/**
 * SearchCacheManager - Hybrid KV/R2 storage for large payloads
 * Handles KV's 2MB limit by automatically falling back to R2 for large data
 */

import type { KVNamespace, R2Bucket } from '@cloudflare/workers-types';
import { createHash } from 'crypto';

export interface CacheOptions {
  ttl?: number; // Time to live in seconds
  namespace?: string; // Cache namespace for organization
  compress?: boolean; // Enable compression for large payloads
}

export interface CacheMetadata {
  type: 'direct' | 'r2-pointer' | 'compressed';
  size: number;
  timestamp: number;
  ttl?: number;
  namespace?: string;
  compressed?: boolean;
  hash?: string;
}

export interface R2Pointer {
  type: 'r2-pointer';
  location: string;
  size: number;
  hash: string;
  timestamp: number;
}

export class SearchCacheManager {
  private static readonly MAX_KV_SIZE = 2 * 1024 * 1024; // 2MB KV limit
  private static readonly SAFE_KV_SIZE = 1.8 * 1024 * 1024; // 1.8MB safety margin
  private static readonly COMPRESSION_THRESHOLD = 100 * 1024; // Compress if > 100KB
  private static readonly DEFAULT_TTL = 300; // 5 minutes
  private static readonly MAX_TTL = 86400; // 24 hours

  constructor(
    private readonly kv: KVNamespace,
    private readonly r2: R2Bucket,
    private readonly enableCompression: boolean = true
  ) {}

  /**
   * Cache search results with automatic KV/R2 routing
   */
  async cacheSearchResults(
    key: string,
    results: any,
    options: CacheOptions = {}
  ): Promise<void> {
    const startTime = Date.now();
    const ttl = this.validateTTL(options.ttl);

    try {
      // Serialize data
      const data = JSON.stringify(results);
      let dataToStore = data;
      let isCompressed = false;

      // Calculate size
      const dataSize = new TextEncoder().encode(data).length;

      // Try compression if enabled and data is large enough
      if (this.enableCompression && options.compress !== false && dataSize > this.COMPRESSION_THRESHOLD) {
        const compressed = await this.compress(data);
        const compressedSize = compressed.length;

        // Only use compression if it actually saves space
        if (compressedSize < dataSize * 0.9) {
          dataToStore = compressed;
          isCompressed = true;
        }
      }

      const finalSize = isCompressed
        ? (dataToStore as Uint8Array).length
        : new TextEncoder().encode(dataToStore as string).length;

      // Decide storage strategy based on size
      if (finalSize < this.SAFE_KV_SIZE) {
        // Small enough for KV
        await this.storeInKV(key, dataToStore, {
          ttl,
          metadata: {
            type: isCompressed ? 'compressed' : 'direct',
            size: finalSize,
            timestamp: Date.now(),
            ttl,
            namespace: options.namespace,
            compressed: isCompressed,
          },
        });
      } else {
        // Too large for KV, use R2 with KV pointer
        await this.storeInR2WithPointer(key, dataToStore, {
          ttl,
          namespace: options.namespace,
          isCompressed,
          originalSize: dataSize,
          compressedSize: finalSize,
        });
      }

      // Log caching metrics
      const duration = Date.now() - startTime;
      console.log(`Cached ${key}: ${finalSize} bytes in ${duration}ms (${finalSize < this.SAFE_KV_SIZE ? 'KV' : 'R2'})`);
    } catch (error) {
      console.error(`Failed to cache ${key}:`, error);
      // Don't throw - caching failures shouldn't break the application
    }
  }

  /**
   * Retrieve cached search results from KV or R2
   */
  async getCachedResults<T = any>(key: string): Promise<T | null> {
    try {
      // First, try to get from KV
      const kvResult = await this.kv.get(key, { type: 'text' });

      if (!kvResult) {
        return null;
      }

      // Check if it's a pointer to R2
      try {
        const parsed = JSON.parse(kvResult);

        if (parsed.type === 'r2-pointer') {
          // Fetch from R2
          return await this.fetchFromR2<T>(parsed as R2Pointer);
        }

        // Direct data in KV
        return parsed as T;
      } catch {
        // Not JSON, might be compressed
        const metadata = await this.kv.getWithMetadata<CacheMetadata>(key);

        if (metadata?.metadata?.compressed) {
          const decompressed = await this.decompress(kvResult);
          return JSON.parse(decompressed) as T;
        }

        // Plain text data
        return JSON.parse(kvResult) as T;
      }
    } catch (error) {
      console.error(`Failed to retrieve cached ${key}:`, error);
      return null;
    }
  }

  /**
   * Store data directly in KV
   */
  private async storeInKV(
    key: string,
    data: string | Uint8Array,
    options: { ttl: number; metadata: CacheMetadata }
  ): Promise<void> {
    if (data instanceof Uint8Array) {
      // Store compressed data as base64
      const base64 = btoa(String.fromCharCode(...data));
      await this.kv.put(key, base64, {
        expirationTtl: options.ttl,
        metadata: options.metadata,
      });
    } else {
      await this.kv.put(key, data, {
        expirationTtl: options.ttl,
        metadata: options.metadata,
      });
    }
  }

  /**
   * Store data in R2 with a pointer in KV
   */
  private async storeInR2WithPointer(
    key: string,
    data: string | Uint8Array,
    options: {
      ttl: number;
      namespace?: string;
      isCompressed: boolean;
      originalSize: number;
      compressedSize: number;
    }
  ): Promise<void> {
    // Generate R2 key with namespace and timestamp
    const timestamp = Date.now();
    const namespace = options.namespace || 'default';
    const r2Key = `cache/${namespace}/${key}-${timestamp}`;

    // Calculate hash for integrity
    const hash = await this.calculateHash(data);

    // Store in R2
    await this.r2.put(r2Key, data, {
      customMetadata: {
        cacheKey: key,
        namespace,
        originalSize: options.originalSize.toString(),
        compressedSize: options.compressedSize.toString(),
        compressed: options.isCompressed.toString(),
        timestamp: timestamp.toString(),
        hash,
      },
      httpMetadata: {
        contentType: options.isCompressed ? 'application/octet-stream' : 'application/json',
      },
    });

    // Store pointer in KV
    const pointer: R2Pointer = {
      type: 'r2-pointer',
      location: r2Key,
      size: options.compressedSize,
      hash,
      timestamp,
    };

    await this.kv.put(key, JSON.stringify(pointer), {
      expirationTtl: options.ttl,
      metadata: {
        type: 'r2-pointer',
        size: options.compressedSize,
        timestamp,
        ttl: options.ttl,
        namespace: options.namespace,
      },
    });

    // Schedule R2 cleanup (could be done via Durable Object or Queue)
    this.scheduleR2Cleanup(r2Key, options.ttl);
  }

  /**
   * Fetch data from R2 using pointer
   */
  private async fetchFromR2<T>(pointer: R2Pointer): Promise<T | null> {
    try {
      const object = await this.r2.get(pointer.location);

      if (!object) {
        console.warn(`R2 object not found: ${pointer.location}`);
        return null;
      }

      // Verify integrity
      const data = await object.arrayBuffer();
      const hash = await this.calculateHash(new Uint8Array(data));

      if (hash !== pointer.hash) {
        console.error(`Hash mismatch for R2 object: ${pointer.location}`);
        return null;
      }

      // Check if compressed
      const metadata = object.customMetadata;
      let content: string;

      if (metadata?.compressed === 'true') {
        content = await this.decompress(new Uint8Array(data));
      } else {
        content = new TextDecoder().decode(data);
      }

      return JSON.parse(content) as T;
    } catch (error) {
      console.error(`Failed to fetch from R2:`, error);
      return null;
    }
  }

  /**
   * Delete cached data (both KV and R2 if applicable)
   */
  async deleteCached(key: string): Promise<void> {
    try {
      // Check if it's an R2 pointer
      const value = await this.kv.get(key);

      if (value) {
        try {
          const parsed = JSON.parse(value);
          if (parsed.type === 'r2-pointer') {
            // Delete from R2
            await this.r2.delete(parsed.location);
          }
        } catch {
          // Not a pointer, just KV data
        }
      }

      // Delete from KV
      await this.kv.delete(key);
    } catch (error) {
      console.error(`Failed to delete cached ${key}:`, error);
    }
  }

  /**
   * Compress data using CompressionStream API
   */
  private async compress(data: string): Promise<Uint8Array> {
    const encoder = new TextEncoder();
    const input = encoder.encode(data);

    const cs = new CompressionStream('gzip');
    const writer = cs.writable.getWriter();
    writer.write(input);
    writer.close();

    const chunks: Uint8Array[] = [];
    const reader = cs.readable.getReader();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    // Combine chunks
    const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;

    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    return result;
  }

  /**
   * Decompress data using DecompressionStream API
   */
  private async decompress(data: string | Uint8Array): Promise<string> {
    let input: Uint8Array;

    if (typeof data === 'string') {
      // Decode base64
      const binaryString = atob(data);
      input = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        input[i] = binaryString.charCodeAt(i);
      }
    } else {
      input = data;
    }

    const ds = new DecompressionStream('gzip');
    const writer = ds.writable.getWriter();
    writer.write(input);
    writer.close();

    const chunks: Uint8Array[] = [];
    const reader = ds.readable.getReader();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    // Combine and decode
    const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;

    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    return new TextDecoder().decode(result);
  }

  /**
   * Calculate SHA-256 hash for integrity verification
   */
  private async calculateHash(data: string | Uint8Array): Promise<string> {
    const encoder = new TextEncoder();
    const input = typeof data === 'string' ? encoder.encode(data) : data;

    const hashBuffer = await crypto.subtle.digest('SHA-256', input);
    const hashArray = Array.from(new Uint8Array(hashBuffer));

    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  }

  /**
   * Validate and constrain TTL
   */
  private validateTTL(ttl?: number): number {
    if (!ttl) return this.DEFAULT_TTL;
    return Math.min(Math.max(ttl, 1), this.MAX_TTL);
  }

  /**
   * Schedule R2 cleanup (placeholder - implement with Queues or Durable Objects)
   */
  private scheduleR2Cleanup(r2Key: string, ttl: number): void {
    // In production, this would schedule a cleanup job
    // For now, just log
    console.log(`Scheduled cleanup for ${r2Key} in ${ttl} seconds`);
  }

  /**
   * Get cache statistics
   */
  async getCacheStats(): Promise<{
    kvCount: number;
    r2Count: number;
    totalSize: number;
  }> {
    // This would require listing KV keys and R2 objects
    // Placeholder implementation
    return {
      kvCount: 0,
      r2Count: 0,
      totalSize: 0,
    };
  }
}