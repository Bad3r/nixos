/**
 * SafeAnalytics - Analytics Engine wrapper with safety limits
 * Handles 16KB blob limit and 25 data points per invocation
 */

import type { AnalyticsEngineDataset } from '@cloudflare/workers-types';

export interface AnalyticsConfig {
  enableSampling?: boolean;
  samplingRate?: number; // 0-1, where 1 = 100% sampling
  enableBatching?: boolean;
  batchSize?: number;
  flushInterval?: number; // milliseconds
}

export interface AnalyticsEvent {
  type: 'search' | 'view' | 'update' | 'error' | 'cache_hit' | 'cache_miss';
  timestamp?: number;
  [key: string]: any;
}

export class SafeAnalytics {
  // Analytics Engine limits
  private static readonly MAX_BLOB_SIZE = 16 * 1024; // 16KB per blob
  private static readonly MAX_BLOB1_SIZE = 5 * 1024; // 5KB for blob1 (recommended)
  private static readonly MAX_STRING_LENGTH = 1024; // 1KB per string (safe limit)
  private static readonly MAX_BLOBS = 20; // Maximum blobs per write
  private static readonly MAX_DOUBLES = 20; // Maximum doubles per write
  private static readonly MAX_DATA_POINTS = 25; // Total limit per invocation

  // Batching
  private batchQueue: any[] = [];
  private batchTimer: number | null = null;

  constructor(
    private readonly analytics: AnalyticsEngineDataset,
    private readonly config: AnalyticsConfig = {}
  ) {
    // Set defaults
    this.config.samplingRate = this.config.samplingRate ?? 1.0;
    this.config.batchSize = this.config.batchSize ?? 10;
    this.config.flushInterval = this.config.flushInterval ?? 5000;
  }

  /**
   * Write a search query event
   */
  async writeSearchQuery(
    query: string,
    results: number,
    duration: number,
    metadata?: Record<string, any>
  ): Promise<void> {
    // Apply sampling
    if (!this.shouldSample()) return;

    const event = {
      type: 'search',
      query: this.truncateString(query, 100),
      queryHash: await this.hashString(query),
      resultCount: results,
      duration,
      timestamp: Date.now(),
      ...this.sanitizeMetadata(metadata),
    };

    await this.writeEvent(event);
  }

  /**
   * Write a module view event
   */
  async writeModuleView(
    moduleId: string,
    namespace: string,
    referrer?: string,
    metadata?: Record<string, any>
  ): Promise<void> {
    if (!this.shouldSample()) return;

    const event = {
      type: 'view',
      moduleId: this.truncateString(moduleId, 200),
      namespace: this.truncateString(namespace, 50),
      referrer: referrer ? this.truncateString(referrer, 200) : undefined,
      timestamp: Date.now(),
      ...this.sanitizeMetadata(metadata),
    };

    await this.writeEvent(event);
  }

  /**
   * Write an error event
   */
  async writeError(
    error: Error | string,
    context: Record<string, any> = {}
  ): Promise<void> {
    // Always log errors (no sampling)
    const errorMessage = error instanceof Error ? error.message : error;
    const errorStack = error instanceof Error ? error.stack : undefined;

    const event = {
      type: 'error',
      message: this.truncateString(errorMessage, 500),
      stack: errorStack ? this.truncateString(errorStack, 1000) : undefined,
      stackHash: errorStack ? await this.hashString(errorStack) : undefined,
      timestamp: Date.now(),
      ...this.sanitizeMetadata(context),
    };

    await this.writeEvent(event, true); // Force immediate write for errors
  }

  /**
   * Write cache performance metrics
   */
  async writeCacheMetrics(
    cacheKey: string,
    hit: boolean,
    latency: number,
    size?: number
  ): Promise<void> {
    if (!this.shouldSample()) return;

    const event = {
      type: hit ? 'cache_hit' : 'cache_miss',
      keyHash: await this.hashString(cacheKey),
      latency,
      size: size || 0,
      timestamp: Date.now(),
    };

    await this.writeEvent(event);
  }

  /**
   * Write a generic analytics event
   */
  private async writeEvent(event: any, immediate: boolean = false): Promise<void> {
    try {
      // Convert event to Analytics Engine format
      const dataPoint = await this.eventToDataPoint(event);

      if (this.config.enableBatching && !immediate) {
        this.addToBatch(dataPoint);
      } else {
        this.analytics.writeDataPoint(dataPoint);
      }
    } catch (error) {
      // Log but don't throw - analytics shouldn't break the app
      console.error('Analytics write failed:', error);
    }
  }

  /**
   * Convert event object to Analytics Engine data point
   */
  private async eventToDataPoint(event: any): Promise<any> {
    const indexes: string[] = [];
    const blobs: (string | ArrayBuffer)[] = [];
    const doubles: number[] = [];

    // Always include event type as first index
    if (event.type) {
      indexes.push(event.type);
    }

    // Process event properties
    for (const [key, value] of Object.entries(event)) {
      if (key === 'type') continue; // Already added

      // Skip null/undefined values
      if (value == null) continue;

      // Handle different value types
      if (typeof value === 'string') {
        if (indexes.length < 5 && value.length <= 50) {
          // Short strings as indexes (for filtering)
          indexes.push(this.truncateString(value, 50));
        } else if (blobs.length < this.MAX_BLOBS) {
          // Longer strings as blobs
          const truncated = this.truncateForBlob(value, key);
          blobs.push(truncated);
        }
      } else if (typeof value === 'number') {
        if (doubles.length < this.MAX_DOUBLES) {
          doubles.push(value);
        }
      } else if (typeof value === 'boolean') {
        if (doubles.length < this.MAX_DOUBLES) {
          doubles.push(value ? 1 : 0);
        }
      } else if (value instanceof ArrayBuffer || value instanceof Uint8Array) {
        if (blobs.length < this.MAX_BLOBS) {
          const buffer = value instanceof Uint8Array ? value.buffer : value;
          const truncated = this.truncateArrayBuffer(buffer, this.MAX_BLOB1_SIZE);
          blobs.push(truncated);
        }
      }
    }

    // Ensure we don't exceed the 25 data point limit
    const totalPoints = indexes.length + blobs.length + doubles.length;
    if (totalPoints > this.MAX_DATA_POINTS) {
      console.warn(`Data point limit exceeded: ${totalPoints} > ${this.MAX_DATA_POINTS}`);

      // Trim to fit within limits
      const maxIndexes = 5;
      const maxBlobs = 10;
      const maxDoubles = 10;

      if (indexes.length > maxIndexes) indexes.splice(maxIndexes);
      if (blobs.length > maxBlobs) blobs.splice(maxBlobs);
      if (doubles.length > maxDoubles) doubles.splice(maxDoubles);
    }

    return {
      indexes,
      blobs,
      doubles,
    };
  }

  /**
   * Truncate string for blob storage
   */
  private truncateForBlob(str: string, key: string): string {
    // Use smaller limit for blob1, larger for others
    const maxLength = key === 'query' || key === 'message'
      ? this.MAX_BLOB1_SIZE
      : this.MAX_STRING_LENGTH;

    if (str.length <= maxLength) return str;

    // For very long strings, include hash for reference
    if (str.length > maxLength * 2) {
      const truncated = str.substring(0, maxLength - 20);
      const hashPromise = this.hashString(str);
      // Note: This is sync for now, but could be async
      return `${truncated}...[h:${this.syncHash(str).substring(0, 8)}]`;
    }

    return str.substring(0, maxLength - 3) + '...';
  }

  /**
   * Truncate ArrayBuffer for blob storage
   */
  private truncateArrayBuffer(buffer: ArrayBuffer, maxSize: number): ArrayBuffer {
    if (buffer.byteLength <= maxSize) return buffer;
    return buffer.slice(0, maxSize);
  }

  /**
   * Truncate string to specified length
   */
  private truncateString(str: string, maxLength: number): string {
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength - 3) + '...';
  }

  /**
   * Hash string using SHA-256 (async)
   */
  private async hashString(str: string): Promise<string> {
    const encoder = new TextEncoder();
    const data = encoder.encode(str);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('').substring(0, 16);
  }

  /**
   * Synchronous hash for immediate use (less secure, but fast)
   */
  private syncHash(str: string): string {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash).toString(16);
  }

  /**
   * Sanitize metadata object for analytics
   */
  private sanitizeMetadata(metadata?: Record<string, any>): Record<string, any> {
    if (!metadata) return {};

    const sanitized: Record<string, any> = {};

    for (const [key, value] of Object.entries(metadata)) {
      // Skip complex objects
      if (typeof value === 'object' && value !== null && !(value instanceof Date)) {
        continue;
      }

      // Sanitize key (remove special characters)
      const safeKey = key.replace(/[^a-zA-Z0-9_]/g, '_').substring(0, 50);

      // Sanitize value
      if (typeof value === 'string') {
        sanitized[safeKey] = this.truncateString(value, 200);
      } else if (typeof value === 'number') {
        sanitized[safeKey] = isFinite(value) ? value : 0;
      } else if (typeof value === 'boolean') {
        sanitized[safeKey] = value;
      } else if (value instanceof Date) {
        sanitized[safeKey] = value.getTime();
      }
    }

    return sanitized;
  }

  /**
   * Check if event should be sampled
   */
  private shouldSample(): boolean {
    if (!this.config.enableSampling) return true;
    return Math.random() < (this.config.samplingRate || 1.0);
  }

  /**
   * Add event to batch queue
   */
  private addToBatch(dataPoint: any): void {
    this.batchQueue.push(dataPoint);

    // Flush if batch size reached
    if (this.batchQueue.length >= (this.config.batchSize || 10)) {
      this.flushBatch();
      return;
    }

    // Set up flush timer if not already set
    if (this.batchTimer === null) {
      this.batchTimer = setTimeout(() => {
        this.flushBatch();
      }, this.config.flushInterval || 5000) as any;
    }
  }

  /**
   * Flush batched events
   */
  private flushBatch(): void {
    if (this.batchQueue.length === 0) return;

    // Write all batched events
    for (const dataPoint of this.batchQueue) {
      try {
        this.analytics.writeDataPoint(dataPoint);
      } catch (error) {
        console.error('Failed to write batched analytics:', error);
      }
    }

    // Clear batch
    this.batchQueue = [];

    // Clear timer
    if (this.batchTimer !== null) {
      clearTimeout(this.batchTimer);
      this.batchTimer = null;
    }
  }

  /**
   * Force flush all pending analytics
   */
  async flush(): Promise<void> {
    this.flushBatch();
  }

  /**
   * Create aggregated metrics report
   */
  async createMetricsReport(
    startTime: number,
    endTime: number
  ): Promise<Record<string, any>> {
    // This would typically query Analytics Engine SQL API
    // Placeholder for now
    return {
      period: {
        start: new Date(startTime).toISOString(),
        end: new Date(endTime).toISOString(),
      },
      metrics: {
        totalSearches: 0,
        averageSearchLatency: 0,
        cacheHitRate: 0,
        errorRate: 0,
      },
    };
  }
}