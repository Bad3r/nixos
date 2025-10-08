/**
 * PR Preview Handler - Temporary preview deployments for pull requests
 * Allows testing module documentation changes before merging
 */

import { Context } from "hono";
import type { Env } from "../../types";
import { prPreviewSchema } from "../../validation/schemas";
import { validateBody } from "../../middleware/validation";

type PreviewContext = Context<{
  Bindings: Env;
  Variables: Record<string, unknown>;
}>;

export class PreviewHandler {
  private static readonly PREVIEW_TTL = 24 * 60 * 60; // 24 hours
  private static readonly MAX_PREVIEW_SIZE = 5 * 1024 * 1024; // 5MB
  private static readonly PREVIEW_PREFIX = "preview:pr:";

  /**
   * Create a preview deployment for a PR
   */
  async handleCreatePreview(c: PreviewContext) {
    try {
      // Get validated data
      const { prNumber, modules, branch, sha } = c.get("body") as {
        prNumber: number;
        modules: any[];
        branch?: string;
        sha?: string;
      };

      // Generate preview key
      const previewKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}`;
      const previewMetaKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}:meta`;

      // Check if preview already exists
      const existing = await c.env.CACHE.get(previewMetaKey);
      if (existing) {
        const meta = JSON.parse(existing);

        // If same SHA, return existing preview
        if (meta.sha === sha) {
          return c.json({
            success: true,
            message: "Preview already exists",
            previewUrl: meta.previewUrl,
            prNumber,
            expiresAt: meta.expiresAt,
            cached: true,
          });
        }
      }

      // Prepare preview data
      const previewData = {
        modules,
        timestamp: Date.now(),
        prNumber,
        branch: branch || "unknown",
        sha: sha || "unknown",
        moduleCount: modules.length,
      };

      // Check size
      const dataSize = new TextEncoder().encode(
        JSON.stringify(previewData),
      ).length;
      if (dataSize > PreviewHandler.MAX_PREVIEW_SIZE) {
        return c.json(
          {
            error: "Preview data too large",
            maxSize: PreviewHandler.MAX_PREVIEW_SIZE,
            actualSize: dataSize,
          },
          413,
        );
      }

      // Store preview data
      await this.storePreviewData(c.env, previewKey, previewData);

      // Generate preview URLs
      const baseUrl = this.getBaseUrl(c);
      const previewUrl = `${baseUrl}/preview/${prNumber}`;
      const apiPreviewUrl = `${baseUrl}/api/v1/preview/${prNumber}`;

      // Store metadata
      const metadata = {
        prNumber,
        branch,
        sha,
        moduleCount: modules.length,
        createdAt: new Date().toISOString(),
        expiresAt: new Date(
          Date.now() + PreviewHandler.PREVIEW_TTL * 1000,
        ).toISOString(),
        previewUrl,
        apiPreviewUrl,
        size: dataSize,
      };

      await c.env.CACHE.put(previewMetaKey, JSON.stringify(metadata), {
        expirationTtl: PreviewHandler.PREVIEW_TTL,
        metadata: {
          type: "preview-meta",
          pr: prNumber.toString(),
        },
      });

      // Track analytics
      if (c.env.ANALYTICS) {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ["preview_created", `pr_${prNumber}`],
          doubles: [prNumber, modules.length, dataSize, Date.now()],
          blobs: [branch || "", sha ? sha.substring(0, 8) : ""],
        });
      }

      return c.json(
        {
          success: true,
          message: "Preview created successfully",
          previewUrl,
          apiPreviewUrl,
          prNumber,
          moduleCount: modules.length,
          branch,
          sha: sha?.substring(0, 8),
          expiresAt: metadata.expiresAt,
          size: dataSize,
        },
        201,
      );
    } catch (error) {
      console.error("Preview creation failed:", error);
      return c.json(
        {
          error: "Failed to create preview",
          message: error instanceof Error ? error.message : "Unknown error",
        },
        500,
      );
    }
  }

  /**
   * Get preview data for a PR
   */
  async handleGetPreview(c: PreviewContext) {
    try {
      const prNumber = c.req.param("pr");

      if (!prNumber || !/^\d+$/.test(prNumber)) {
        return c.json({ error: "Invalid PR number" }, 400);
      }

      const previewKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}`;
      const previewMetaKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}:meta`;

      // Get metadata first
      const metaData = await c.env.CACHE.get(previewMetaKey);
      if (!metaData) {
        return c.json(
          {
            error: "Preview not found",
            message: `No preview exists for PR #${prNumber}`,
          },
          404,
        );
      }

      const metadata = JSON.parse(metaData);

      // Get actual preview data
      const previewData = await this.getPreviewData(c.env, previewKey);
      if (!previewData) {
        return c.json(
          {
            error: "Preview data not found",
            message: "Preview metadata exists but data is missing",
          },
          404,
        );
      }

      // Track view analytics
      if (c.env.ANALYTICS) {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ["preview_viewed", `pr_${prNumber}`],
          doubles: [parseInt(prNumber), Date.now()],
        });
      }

      return c.json({
        success: true,
        preview: {
          ...metadata,
          modules: previewData.modules,
        },
      });
    } catch (error) {
      console.error("Preview retrieval failed:", error);
      return c.json(
        {
          error: "Failed to retrieve preview",
          message: error instanceof Error ? error.message : "Unknown error",
        },
        500,
      );
    }
  }

  /**
   * Delete a preview
   */
  async handleDeletePreview(c: PreviewContext) {
    try {
      const prNumber = c.req.param("pr");

      if (!prNumber || !/^\d+$/.test(prNumber)) {
        return c.json({ error: "Invalid PR number" }, 400);
      }

      const previewKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}`;
      const previewMetaKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}:meta`;
      const previewChunksPrefix = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}:chunk:`;

      // Check if preview exists
      const exists = await c.env.CACHE.get(previewMetaKey);
      if (!exists) {
        return c.json(
          {
            error: "Preview not found",
            message: `No preview exists for PR #${prNumber}`,
          },
          404,
        );
      }

      // Delete all related keys
      await Promise.all([
        c.env.CACHE.delete(previewKey),
        c.env.CACHE.delete(previewMetaKey),
        // Delete any chunks if data was split
        this.deleteChunks(c.env, previewChunksPrefix),
      ]);

      // Track deletion
      if (c.env.ANALYTICS) {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ["preview_deleted", `pr_${prNumber}`],
          doubles: [parseInt(prNumber), Date.now()],
        });
      }

      return c.json({
        success: true,
        message: `Preview for PR #${prNumber} deleted successfully`,
      });
    } catch (error) {
      console.error("Preview deletion failed:", error);
      return c.json(
        {
          error: "Failed to delete preview",
          message: error instanceof Error ? error.message : "Unknown error",
        },
        500,
      );
    }
  }

  /**
   * List all active previews
   */
  async handleListPreviews(c: PreviewContext) {
    try {
      // KV doesn't support listing by prefix in Workers, so we'd need to:
      // 1. Store a list of active previews in a separate key
      // 2. Or use Durable Objects to maintain state
      // For now, return a placeholder

      // In production, you'd maintain an index
      const indexKey = "preview:index";
      const indexData = await c.env.CACHE.get(indexKey);

      if (!indexData) {
        return c.json({
          success: true,
          previews: [],
          total: 0,
        });
      }

      const index = JSON.parse(indexData);
      const previews = [];

      // Fetch metadata for each preview
      for (const prNumber of index.activePreviews || []) {
        const metaKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}:meta`;
        const metaData = await c.env.CACHE.get(metaKey);

        if (metaData) {
          previews.push(JSON.parse(metaData));
        }
      }

      return c.json({
        success: true,
        previews,
        total: previews.length,
      });
    } catch (error) {
      console.error("Preview listing failed:", error);
      return c.json(
        {
          error: "Failed to list previews",
          message: error instanceof Error ? error.message : "Unknown error",
        },
        500,
      );
    }
  }

  /**
   * Update preview (partial update)
   */
  async handleUpdatePreview(c: PreviewContext) {
    try {
      const prNumber = c.req.param("pr");
      const updates = await c.req.json<{
        modules?: any[];
        branch?: string;
        sha?: string;
      }>();

      if (!prNumber || !/^\d+$/.test(prNumber)) {
        return c.json({ error: "Invalid PR number" }, 400);
      }

      const previewKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}`;
      const previewMetaKey = `${PreviewHandler.PREVIEW_PREFIX}${prNumber}:meta`;

      // Get existing preview
      const existingData = await this.getPreviewData(c.env, previewKey);
      if (!existingData) {
        return c.json(
          {
            error: "Preview not found",
            message: `No preview exists for PR #${prNumber}`,
          },
          404,
        );
      }

      // Merge updates
      const updatedData = {
        ...existingData,
        ...(updates.modules && { modules: updates.modules }),
        timestamp: Date.now(),
        lastUpdated: new Date().toISOString(),
      };

      // Store updated data
      await this.storePreviewData(c.env, previewKey, updatedData);

      // Update metadata if needed
      if (updates.branch || updates.sha) {
        const metaData = await c.env.CACHE.get(previewMetaKey);
        if (metaData) {
          const metadata = JSON.parse(metaData);
          const updatedMeta = {
            ...metadata,
            ...(updates.branch && { branch: updates.branch }),
            ...(updates.sha && { sha: updates.sha }),
            lastUpdated: new Date().toISOString(),
          };

          await c.env.CACHE.put(previewMetaKey, JSON.stringify(updatedMeta), {
            expirationTtl: PreviewHandler.PREVIEW_TTL,
            metadata: {
              type: "preview-meta",
              pr: prNumber,
            },
          });
        }
      }

      return c.json({
        success: true,
        message: `Preview for PR #${prNumber} updated successfully`,
        prNumber: parseInt(prNumber),
      });
    } catch (error) {
      console.error("Preview update failed:", error);
      return c.json(
        {
          error: "Failed to update preview",
          message: error instanceof Error ? error.message : "Unknown error",
        },
        500,
      );
    }
  }

  /**
   * Store preview data (handles chunking for large data)
   */
  private async storePreviewData(
    env: Env,
    key: string,
    data: any,
  ): Promise<void> {
    const serialized = JSON.stringify(data);
    const maxChunkSize = 2 * 1024 * 1024 - 1024; // 2MB - 1KB safety margin

    if (serialized.length <= maxChunkSize) {
      // Store directly
      await env.CACHE.put(key, serialized, {
        expirationTtl: PreviewHandler.PREVIEW_TTL,
        metadata: {
          type: "preview-data",
          chunked: false,
        },
      });
    } else {
      // Split into chunks
      const chunks = this.splitIntoChunks(serialized, maxChunkSize);

      // Store chunk index
      await env.CACHE.put(
        key,
        JSON.stringify({
          chunked: true,
          chunkCount: chunks.length,
          totalSize: serialized.length,
        }),
        {
          expirationTtl: PreviewHandler.PREVIEW_TTL,
          metadata: {
            type: "preview-index",
            chunked: true,
          },
        },
      );

      // Store each chunk
      for (let i = 0; i < chunks.length; i++) {
        await env.CACHE.put(`${key}:chunk:${i}`, chunks[i], {
          expirationTtl: PreviewHandler.PREVIEW_TTL,
          metadata: {
            type: "preview-chunk",
            index: i,
            total: chunks.length,
          },
        });
      }
    }
  }

  /**
   * Get preview data (handles chunked data)
   */
  private async getPreviewData(env: Env, key: string): Promise<any | null> {
    const data = await env.CACHE.get(key);
    if (!data) return null;

    try {
      const parsed = JSON.parse(data);

      if (parsed.chunked) {
        // Reassemble chunks
        const chunks: string[] = [];

        for (let i = 0; i < parsed.chunkCount; i++) {
          const chunk = await env.CACHE.get(`${key}:chunk:${i}`);
          if (!chunk) {
            console.error(`Missing chunk ${i} for ${key}`);
            return null;
          }
          chunks.push(chunk);
        }

        const reassembled = chunks.join("");
        return JSON.parse(reassembled);
      }

      // Not chunked, return directly
      return parsed;
    } catch {
      // Raw data, not chunked
      return JSON.parse(data);
    }
  }

  /**
   * Split string into chunks
   */
  private splitIntoChunks(str: string, chunkSize: number): string[] {
    const chunks: string[] = [];

    for (let i = 0; i < str.length; i += chunkSize) {
      chunks.push(str.slice(i, i + chunkSize));
    }

    return chunks;
  }

  /**
   * Delete all chunks for a preview
   */
  private async deleteChunks(env: Env, prefix: string): Promise<void> {
    // KV doesn't support prefix deletion, so in production you'd:
    // 1. Maintain a list of chunks
    // 2. Or use a different storage strategy

    // For now, try to delete up to 10 chunks (reasonable limit)
    const deletePromises = [];
    for (let i = 0; i < 10; i++) {
      deletePromises.push(env.CACHE.delete(`${prefix}${i}`));
    }

    await Promise.all(deletePromises);
  }

  /**
   * Get base URL for preview links
   */
  private getBaseUrl(c: Context): string {
    const url = new URL(c.req.url);

    // Check if we're in a preview deployment
    if (url.hostname.includes("preview-")) {
      return `${url.protocol}//${url.hostname}`;
    }

    // Check environment
    const env = c.env.ENVIRONMENT;

    if (env === "production") {
      return "https://nixos-modules.org";
    } else if (env === "staging") {
      return "https://staging.nixos-modules.org";
    } else {
      return `${url.protocol}//${url.host}`;
    }
  }
}

// Create singleton instance
const handler = new PreviewHandler();

// Export middleware with properly bound methods
export const previewRoutes = {
  create: [
    validateBody(prPreviewSchema),
    handler.handleCreatePreview.bind(handler),
  ],
  get: handler.handleGetPreview.bind(handler),
  update: handler.handleUpdatePreview.bind(handler),
  delete: handler.handleDeletePreview.bind(handler),
  list: handler.handleListPreviews.bind(handler),
};
