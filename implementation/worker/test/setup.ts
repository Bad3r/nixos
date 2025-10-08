/**
 * Test setup file for Vitest
 * Configures test environment and global utilities
 */

import { beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import { mockDeep } from 'vitest-mock-extended';
import type { Env } from '../src/types';

// Global test utilities
declare global {
  var testEnv: Env;
  var testHelpers: {
    createMockRequest: (url: string, options?: RequestInit) => Request;
    createMockContext: () => any;
    waitForAsync: (ms: number) => Promise<void>;
  };
}

// Setup before all tests
beforeAll(() => {
  // Set up global test environment
  global.testEnv = createMockEnv();

  // Set up test helpers
  global.testHelpers = {
    createMockRequest: (url: string, options?: RequestInit) => {
      return new Request(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
        ...options,
      });
    },

    createMockContext: () => {
      return {
        env: global.testEnv,
        executionContext: {
          waitUntil: (promise: Promise<any>) => promise,
          passThroughOnException: () => {},
        },
        params: {},
        set: jest.fn(),
        get: jest.fn(),
      };
    },

    waitForAsync: (ms: number) => {
      return new Promise(resolve => setTimeout(resolve, ms));
    },
  };

  // Mock console methods in test
  if (process.env.SILENT_TESTS === 'true') {
    global.console.log = jest.fn();
    global.console.error = jest.fn();
    global.console.warn = jest.fn();
  }
});

// Cleanup after all tests
afterAll(() => {
  // Clean up any resources
  jest.restoreAllMocks();
});

// Setup before each test
beforeEach(() => {
  // Reset mocks
  jest.clearAllMocks();

  // Reset test data
  resetTestData();
});

// Cleanup after each test
afterEach(() => {
  // Clear timers
  jest.clearAllTimers();
});

// Create mock environment
function createMockEnv(): Env {
  return {
    // Mock ASSETS fetcher
    ASSETS: {
      fetch: jest.fn().mockResolvedValue(new Response('Mock asset')),
      connect: jest.fn(),
    } as any,

    // Mock D1 Database
    MODULES_DB: {
      prepare: jest.fn().mockReturnThis(),
      bind: jest.fn().mockReturnThis(),
      first: jest.fn(),
      all: jest.fn(),
      run: jest.fn(),
      batch: jest.fn(),
    } as any,

    // Mock Vectorize
    SEARCH_INDEX: {
      query: jest.fn().mockResolvedValue([]),
      insert: jest.fn().mockResolvedValue(undefined),
      upsert: jest.fn().mockResolvedValue(undefined),
      delete: jest.fn().mockResolvedValue(undefined),
      getByIds: jest.fn().mockResolvedValue([]),
    } as any,

    // Mock KV Namespace
    CACHE: {
      get: jest.fn(),
      getWithMetadata: jest.fn(),
      put: jest.fn().mockResolvedValue(undefined),
      delete: jest.fn().mockResolvedValue(undefined),
      list: jest.fn().mockResolvedValue({ keys: [] }),
    } as any,

    // Mock R2 Bucket
    DOCUMENTS: {
      get: jest.fn(),
      put: jest.fn().mockResolvedValue(undefined),
      delete: jest.fn().mockResolvedValue(undefined),
      list: jest.fn().mockResolvedValue({ objects: [] }),
      head: jest.fn(),
    } as any,

    // Mock Analytics Engine
    ANALYTICS: {
      writeDataPoint: jest.fn(),
    } as any,

    // Mock AI
    AI: {
      run: jest.fn().mockResolvedValue({ response: 'Mock AI response' }),
    } as any,

    // Mock Rate Limiter
    RATE_LIMITER: {
      check: jest.fn().mockResolvedValue({
        success: true,
        limit: 100,
        remaining: 99,
        resetAt: new Date(Date.now() + 60000),
      }),
    } as any,

    // Environment variables
    JWT_SECRET: 'test-jwt-secret-at-least-32-characters',
    API_TOKEN: 'test-api-token-at-least-32-characters',
    CF_ACCESS_AUD: 'test-audience',
    CF_ACCESS_TEAM_DOMAIN: 'test.cloudflareaccess.com',
    ENVIRONMENT: 'test' as any,
    CACHE_TTL: '60',
    MAX_BATCH_SIZE: '10',
    ENABLE_DEBUG: 'true',
  };
}

// Reset test data
function resetTestData(): void {
  // Reset any in-memory stores or caches used in tests
  // This would be implemented based on your specific needs
}

// Export test utilities
export const testUtils = {
  createMockEnv,
  resetTestData,

  // Create mock module data
  createMockModule: (overrides?: any) => ({
    name: 'test-module',
    namespace: 'test',
    description: 'Test module description',
    type: 'nixos',
    options: [],
    declarations: [],
    metadata: {},
    ...overrides,
  }),

  // Create mock search results
  createMockSearchResults: (count: number = 5) => {
    return Array.from({ length: count }, (_, i) => ({
      name: `module-${i}`,
      namespace: 'test',
      description: `Test module ${i} description`,
      score: 1 - (i * 0.1),
    }));
  },

  // Async test helper
  runAsyncTest: async (fn: () => Promise<void>) => {
    try {
      await fn();
    } catch (error) {
      console.error('Async test failed:', error);
      throw error;
    }
  },

  // Mock fetch responses
  mockFetchResponse: (response: any) => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(JSON.stringify(response), {
        headers: { 'Content-Type': 'application/json' },
      })
    );
  },
};

// Extend expect matchers
expect.extend({
  toBeValidUUID(received: string) {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const pass = uuidRegex.test(received);

    return {
      pass,
      message: () => pass
        ? `expected ${received} not to be a valid UUID`
        : `expected ${received} to be a valid UUID`,
    };
  },

  toBeWithinRange(received: number, floor: number, ceiling: number) {
    const pass = received >= floor && received <= ceiling;

    return {
      pass,
      message: () => pass
        ? `expected ${received} not to be within range ${floor} - ${ceiling}`
        : `expected ${received} to be within range ${floor} - ${ceiling}`,
    };
  },
});