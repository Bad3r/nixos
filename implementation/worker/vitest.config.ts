/**
 * Vitest configuration with coverage thresholds
 * Configured for Cloudflare Workers testing with Miniflare
 */

import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    // Enable global test APIs
    globals: true,

    // Use Miniflare environment for Workers testing
    environment: 'miniflare',

    // Environment options
    environmentOptions: {
      bindings: {
        // Test environment bindings
        ENVIRONMENT: 'test',
        JWT_SECRET: 'test-secret-at-least-32-characters-long',
        API_TOKEN: 'test-api-token-at-least-32-characters',
        CACHE_TTL: '60',
        MAX_BATCH_SIZE: '10',
        ENABLE_DEBUG: 'true',
      },
      kvPersist: false, // Use in-memory KV for tests
      d1Persist: false, // Use in-memory D1 for tests
      r2Persist: false, // Use in-memory R2 for tests
    },

    // Setup files
    setupFiles: ['./test/setup.ts'],

    // Test match patterns
    include: [
      'src/**/*.{test,spec}.{js,ts,jsx,tsx}',
      'test/**/*.{test,spec}.{js,ts,jsx,tsx}',
    ],

    // Coverage configuration
    coverage: {
      enabled: true,
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      reportsDirectory: './coverage',

      // Files to include in coverage
      include: [
        'src/**/*.{js,ts,jsx,tsx}',
      ],

      // Files to exclude from coverage
      exclude: [
        'node_modules',
        'test',
        'dist',
        '*.config.ts',
        'src/**/*.d.ts',
        'src/**/*.test.ts',
        'src/**/*.spec.ts',
        'src/types.ts', // Type definitions
      ],

      // Coverage thresholds (80% minimum)
      thresholds: {
        statements: 80,
        branches: 80,
        functions: 80,
        lines: 80,

        // Per-file thresholds for critical files
        perFile: true,
      },

      // Check coverage after all tests
      skipFull: false,

      // Clean coverage before running
      clean: true,

      // Report uncovered lines
      all: true,
    },

    // Test timeout
    testTimeout: 30000,

    // Hook timeout
    hookTimeout: 30000,

    // Retry flaky tests
    retry: 2,

    // Run tests in parallel
    threads: true,
    maxThreads: 4,

    // Watch mode settings
    watch: false,
    watchExclude: ['node_modules', 'dist', 'coverage'],

    // Reporter
    reporters: ['default', 'html'],

    // Output file for HTML reporter
    outputFile: {
      html: './test-results/index.html',
    },

    // Fail on first test failure in CI
    bail: process.env.CI ? 1 : 0,

    // Show heap usage
    logHeapUsage: true,

    // Allow only specific tests in CI
    allowOnly: !process.env.CI,

    // Pool options
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
        isolate: true,
      },
    },

    // Mock configuration
    mockReset: true,
    clearMocks: true,
    restoreMocks: true,
  },

  // Resolve configuration
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@test': path.resolve(__dirname, './test'),
    },
  },

  // Build configuration (for test builds)
  build: {
    target: 'esnext',
    sourcemap: true,
  },

  // Define configuration
  define: {
    'process.env.NODE_ENV': '"test"',
  },
});