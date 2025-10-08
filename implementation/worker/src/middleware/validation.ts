/**
 * Validation middleware using Zod schemas
 * Provides consistent error handling and request validation
 */

import { Context, Next } from 'hono';
import { z, ZodError, ZodSchema } from 'zod';

// Validation middleware factory
export function validate<T>(schema: ZodSchema<T>) {
  return async (c: Context, next: Next) => {
    try {
      // Determine data source based on request method
      let data: unknown;

      const method = c.req.method.toUpperCase();
      const contentType = c.req.header('content-type');

      if (method === 'GET' || method === 'HEAD' || method === 'DELETE') {
        // Parse query parameters
        const url = new URL(c.req.url);
        data = Object.fromEntries(url.searchParams.entries());
      } else if (contentType?.includes('application/json')) {
        // Parse JSON body
        data = await c.req.json();
      } else if (contentType?.includes('application/x-www-form-urlencoded')) {
        // Parse form data
        const formData = await c.req.formData();
        data = Object.fromEntries(formData.entries());
      } else if (contentType?.includes('multipart/form-data')) {
        // Parse multipart form data
        const formData = await c.req.formData();
        data = Object.fromEntries(formData.entries());
      } else {
        // Default to JSON parsing attempt
        try {
          data = await c.req.json();
        } catch {
          data = {};
        }
      }

      // Validate data against schema
      const validated = await schema.parseAsync(data);

      // Store validated data in context for use in handlers
      c.set('validated', validated);
      c.set('validationPassed', true);

      await next();
    } catch (error) {
      if (error instanceof ZodError) {
        // Format Zod errors for API response
        return c.json({
          error: 'Validation failed',
          code: 'VALIDATION_ERROR',
          details: formatZodErrors(error),
          timestamp: new Date().toISOString(),
        }, 400);
      }

      // Re-throw non-Zod errors
      throw error;
    }
  };
}

// Query parameter validation middleware
export function validateQuery<T>(schema: ZodSchema<T>) {
  return async (c: Context, next: Next) => {
    try {
      const url = new URL(c.req.url);
      const queryParams = Object.fromEntries(url.searchParams.entries());

      const validated = await schema.parseAsync(queryParams);
      c.set('query', validated);

      await next();
    } catch (error) {
      if (error instanceof ZodError) {
        return c.json({
          error: 'Invalid query parameters',
          code: 'QUERY_VALIDATION_ERROR',
          details: formatZodErrors(error),
          timestamp: new Date().toISOString(),
        }, 400);
      }
      throw error;
    }
  };
}

// Request body validation middleware
export function validateBody<T>(schema: ZodSchema<T>) {
  return async (c: Context, next: Next) => {
    try {
      const body = await c.req.json();
      const validated = await schema.parseAsync(body);

      c.set('body', validated);

      await next();
    } catch (error) {
      if (error instanceof ZodError) {
        return c.json({
          error: 'Invalid request body',
          code: 'BODY_VALIDATION_ERROR',
          details: formatZodErrors(error),
          timestamp: new Date().toISOString(),
        }, 400);
      }
      throw error;
    }
  };
}

// Path parameter validation middleware
export function validateParams<T>(schema: ZodSchema<T>) {
  return async (c: Context, next: Next) => {
    try {
      const params = c.req.param();
      const validated = await schema.parseAsync(params);

      c.set('params', validated);

      await next();
    } catch (error) {
      if (error instanceof ZodError) {
        return c.json({
          error: 'Invalid path parameters',
          code: 'PARAMS_VALIDATION_ERROR',
          details: formatZodErrors(error),
          timestamp: new Date().toISOString(),
        }, 400);
      }
      throw error;
    }
  };
}

// Header validation middleware
export function validateHeaders<T>(schema: ZodSchema<T>) {
  return async (c: Context, next: Next) => {
    try {
      const headers: Record<string, string> = {};
      c.req.raw.headers.forEach((value, key) => {
        headers[key.toLowerCase()] = value;
      });

      const validated = await schema.parseAsync(headers);
      c.set('headers', validated);

      await next();
    } catch (error) {
      if (error instanceof ZodError) {
        return c.json({
          error: 'Invalid request headers',
          code: 'HEADER_VALIDATION_ERROR',
          details: formatZodErrors(error),
          timestamp: new Date().toISOString(),
        }, 400);
      }
      throw error;
    }
  };
}

// Composite validation for multiple sources
export function validateRequest<T extends {
  query?: ZodSchema<any>;
  body?: ZodSchema<any>;
  params?: ZodSchema<any>;
  headers?: ZodSchema<any>;
}>(schemas: T) {
  return async (c: Context, next: Next) => {
    const errors: any[] = [];
    const validated: any = {};

    // Validate query if schema provided
    if (schemas.query) {
      try {
        const url = new URL(c.req.url);
        const queryParams = Object.fromEntries(url.searchParams.entries());
        validated.query = await schemas.query.parseAsync(queryParams);
      } catch (error) {
        if (error instanceof ZodError) {
          errors.push({
            source: 'query',
            errors: formatZodErrors(error),
          });
        }
      }
    }

    // Validate body if schema provided
    if (schemas.body) {
      try {
        const body = await c.req.json();
        validated.body = await schemas.body.parseAsync(body);
      } catch (error) {
        if (error instanceof ZodError) {
          errors.push({
            source: 'body',
            errors: formatZodErrors(error),
          });
        }
      }
    }

    // Validate params if schema provided
    if (schemas.params) {
      try {
        const params = c.req.param();
        validated.params = await schemas.params.parseAsync(params);
      } catch (error) {
        if (error instanceof ZodError) {
          errors.push({
            source: 'params',
            errors: formatZodErrors(error),
          });
        }
      }
    }

    // Validate headers if schema provided
    if (schemas.headers) {
      try {
        const headers: Record<string, string> = {};
        c.req.raw.headers.forEach((value, key) => {
          headers[key.toLowerCase()] = value;
        });
        validated.headers = await schemas.headers.parseAsync(headers);
      } catch (error) {
        if (error instanceof ZodError) {
          errors.push({
            source: 'headers',
            errors: formatZodErrors(error),
          });
        }
      }
    }

    // Return errors if any validation failed
    if (errors.length > 0) {
      return c.json({
        error: 'Validation failed',
        code: 'MULTI_VALIDATION_ERROR',
        details: errors,
        timestamp: new Date().toISOString(),
      }, 400);
    }

    // Store all validated data
    c.set('validated', validated);
    await next();
  };
}

// Format Zod errors for API response
function formatZodErrors(error: ZodError): any[] {
  return error.errors.map(err => ({
    path: err.path.join('.'),
    message: err.message,
    code: err.code,
    ...(err.expected !== undefined && { expected: err.expected }),
    ...(err.received !== undefined && { received: err.received }),
  }));
}

// Sanitization helper for strings
export function sanitizeString(input: string, maxLength: number = 1000): string {
  return input
    .trim()
    .slice(0, maxLength)
    .replace(/[^\w\s\-\.\/\@]/g, ''); // Remove special chars except common ones
}

// Validation helpers for common patterns
export const validators = {
  isUUID: (value: string): boolean => {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(value);
  },

  isSHA256: (value: string): boolean => {
    const sha256Regex = /^[a-f0-9]{64}$/i;
    return sha256Regex.test(value);
  },

  isValidModuleName: (value: string): boolean => {
    const moduleNameRegex = /^[a-zA-Z][a-zA-Z0-9\-\.]*$/;
    return moduleNameRegex.test(value) && value.length <= 200;
  },

  isValidNamespace: (value: string): boolean => {
    const namespaceRegex = /^[a-z][a-z0-9\-]*$/;
    return namespaceRegex.test(value) && value.length <= 100;
  },

  isValidEmail: (value: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(value);
  },
};