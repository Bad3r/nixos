/**
 * Statistics handler
 * Returns global statistics about modules and usage
 */

import type { Context } from "hono";
import type { Env, Stats } from "../../types";
import { CacheKeys, CacheTTL } from "../../types";

export async function getStats(c: Context<{ Bindings: Env }>) {
  // Generate cache key
  const cacheKey = CacheKeys.stats();

  // Check cache (only if KV binding configured)
  if (c.env.CACHE) {
    try {
      const cached = await c.env.CACHE.get(cacheKey, "json");
      if (cached) {
        c.header("X-Cache", "HIT");
        return c.json(cached);
      }
    } catch (error) {
      console.warn("Cache read error:", error);
    }
  }

  try {
    // Get total modules count
    const moduleCountStmt = c.env.MODULES_DB.prepare(
      "SELECT COUNT(*) as total FROM modules",
    );
    const moduleCount = await moduleCountStmt.first<{ total: number }>();

    // Get total unique hosts count
    const hostCountStmt = c.env.MODULES_DB.prepare(
      "SELECT COUNT(DISTINCT hostname_hash) as total FROM host_usage",
    );
    const hostCount = await hostCountStmt.first<{ total: number }>();

    // Get total options count
    const optionCountStmt = c.env.MODULES_DB.prepare(
      "SELECT COUNT(*) as total FROM module_options",
    );
    const optionCount = await optionCountStmt.first<{ total: number }>();

    // Get most used modules (top 10)
    const mostUsedStmt = c.env.MODULES_DB.prepare(`
      SELECT
        m.path,
        m.name,
        m.namespace,
        COUNT(DISTINCT hu.hostname_hash) as usage_count
      FROM modules m
      LEFT JOIN host_usage hu ON m.path = hu.module_path
      GROUP BY m.id
      HAVING usage_count > 0
      ORDER BY usage_count DESC
      LIMIT 10
    `);
    const mostUsed = await mostUsedStmt.all<{
      path: string;
      name: string;
      namespace: string;
      usage_count: number;
    }>();

    // Get namespace statistics
    const namespaceStmt = c.env.MODULES_DB.prepare(`
      SELECT
        namespace,
        COUNT(*) as module_count
      FROM modules
      GROUP BY namespace
      ORDER BY module_count DESC
    `);
    const namespaces = await namespaceStmt.all<{
      namespace: string;
      module_count: number;
    }>();

    // Get recent activity (modules updated in last 7 days)
    const recentStmt = c.env.MODULES_DB.prepare(`
      SELECT COUNT(*) as total
      FROM modules
      WHERE updated_at > datetime('now', '-7 days')
    `);
    const recentUpdates = await recentStmt.first<{ total: number }>();

    // Get dependency statistics
    const depStatsStmt = c.env.MODULES_DB.prepare(`
      SELECT
        COUNT(*) as total_dependencies,
        COUNT(DISTINCT module_id) as modules_with_deps,
        COUNT(DISTINCT depends_on_path) as unique_dependencies
      FROM module_dependencies
    `);
    const depStats = await depStatsStmt.first<{
      total_dependencies: number;
      modules_with_deps: number;
      unique_dependencies: number;
    }>();

    const stats: Stats & { additional: Record<string, unknown> } = {
      total_modules: Number(moduleCount?.total ?? 0),
      total_hosts: Number(hostCount?.total ?? 0),
      total_options: Number(optionCount?.total ?? 0),
      most_used_modules: mostUsed.results ?? [],
      namespaces: namespaces.results ?? [],
      additional: {
        recent_updates: Number(recentUpdates?.total ?? 0),
        total_dependencies: Number(depStats?.total_dependencies ?? 0),
        modules_with_dependencies: Number(depStats?.modules_with_deps ?? 0),
        unique_dependencies: Number(depStats?.unique_dependencies ?? 0),
      },
    };

    // Get database size (optional, may not work on all D1 versions)
    try {
      const sizeStmt = c.env.MODULES_DB.prepare(`
        SELECT
          page_count * page_size as size_bytes
        FROM pragma_page_count(), pragma_page_size()
      `);
      const dbSize = await sizeStmt.first<{ size_bytes: number }>();
      if (dbSize?.size_bytes) {
        stats.additional.database_size_mb = (
          Number(dbSize.size_bytes) /
          1024 /
          1024
        ).toFixed(2);
      }
    } catch (error) {
      // Ignore if PRAGMA is not supported
    }

    const response = {
      stats,
      timestamp: new Date().toISOString(),
      environment: c.env.ENVIRONMENT || "development",
    };

    // Cache the response (only if KV binding configured)
    if (c.env.CACHE) {
      try {
        await c.env.CACHE.put(cacheKey, JSON.stringify(response), {
          expirationTtl: CacheTTL.stats,
        });
      } catch (error) {
        console.warn("Cache write error:", error);
      }
    }

    // Track stats request in analytics if enabled
    if (c.env.ANALYTICS) {
      try {
        c.env.ANALYTICS.writeDataPoint({
          indexes: ["stats_request"],
          blobs: ["global"],
          doubles: [stats.total_modules, stats.total_hosts, Date.now()],
        });
      } catch (error) {
        console.warn("Analytics write error:", error);
      }
    }

    c.header("X-Cache", "MISS");
    return c.json(response);
  } catch (error) {
    console.error("Stats error:", error);
    return c.json(
      {
        error: "Failed to fetch statistics",
        timestamp: new Date().toISOString(),
      },
      500,
    );
  }
}
