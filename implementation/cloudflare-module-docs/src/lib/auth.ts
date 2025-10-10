/**
 * JWT-based Authentication Module
 * Supports multiple authentication methods:
 * - Cloudflare Access JWT validation
 * - Custom JWT tokens
 * - Service tokens for M2M communication
 */

import {
  jwtVerify,
  SignJWT,
  createRemoteJWKSet,
  importPKCS8,
  importSPKI,
} from "jose";
import { z } from "zod";

// Environment configuration
export interface AuthEnv {
  // JWT Configuration
  JWT_SECRET: string;
  JWT_PUBLIC_KEY?: string;
  JWT_PRIVATE_KEY?: string;

  // Cloudflare Access
  CF_ACCESS_TEAM_DOMAIN?: string;
  CF_ACCESS_AUD?: string;
  CF_ACCESS_SERVICE_TOKEN_ID?: string;
  CF_ACCESS_SERVICE_TOKEN_SECRET?: string;

  // Rate limiting
  API_RATE_LIMITER: RateLimit;
  WRITE_RATE_LIMITER: RateLimit;

  // Database
  MODULES_DB: D1Database;
}

// Token types
export enum TokenType {
  USER = "user",
  SERVICE = "service",
  CLOUDFLARE_ACCESS = "cf_access",
  API_KEY = "api_key", // For backwards compatibility during migration
}

// Permission levels
export enum Permission {
  READ = "read",
  WRITE = "write",
  ADMIN = "admin",
  SUPER_ADMIN = "super_admin",
}

// User context from JWT
export interface AuthContext {
  // Identity
  id: string;
  email?: string;
  name?: string;
  type: TokenType;

  // Permissions
  permissions: Permission[];
  scopes: string[];

  // Metadata
  issuedAt: number;
  expiresAt: number;
  issuer: string;
  audience?: string[];

  // Rate limiting key
  rateLimitKey: string;

  // Additional claims
  groups?: string[];
  metadata?: Record<string, any>;
}

// JWT payload schema
const JWTPayloadSchema = z.object({
  sub: z.string(),
  email: z.string().email().optional(),
  name: z.string().optional(),
  type: z.nativeEnum(TokenType).default(TokenType.USER),
  permissions: z.array(z.nativeEnum(Permission)).default([Permission.READ]),
  scopes: z.array(z.string()).default(["modules:read"]),
  iat: z.number(),
  exp: z.number(),
  iss: z.string(),
  aud: z.union([z.string(), z.array(z.string())]).optional(),
  groups: z.array(z.string()).optional(),
  metadata: z.record(z.any()).optional(),
});

// Service token schema for database storage
const ServiceTokenSchema = z.object({
  id: z.string(),
  name: z.string(),
  token_hash: z.string(),
  permissions: z.array(z.nativeEnum(Permission)),
  scopes: z.array(z.string()),
  created_at: z.string(),
  expires_at: z.string().optional(),
  last_used: z.string().optional(),
  metadata: z.record(z.any()).optional(),
});

/**
 * Main authentication class
 */
export class Auth {
  constructor(private env: AuthEnv) {}

  /**
   * Authenticate a request using multiple strategies
   */
  async authenticate(request: Request): Promise<AuthContext> {
    // Try Cloudflare Access JWT first (highest priority)
    const cfAccessToken = request.headers.get("Cf-Access-Jwt-Assertion");
    if (cfAccessToken) {
      return await this.validateCloudflareAccess(cfAccessToken);
    }

    // Try Bearer token (JWT or Service Token)
    const authHeader = request.headers.get("Authorization");
    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.substring(7);

      // Check if it's a service token (starts with 'st_')
      if (token.startsWith("st_")) {
        return await this.validateServiceToken(token);
      }

      // Otherwise treat as JWT
      return await this.validateJWT(token);
    }

    // Try service token headers (for M2M communication)
    const clientId = request.headers.get("CF-Access-Client-Id");
    const clientSecret = request.headers.get("CF-Access-Client-Secret");
    if (clientId && clientSecret) {
      return await this.validateServiceCredentials(clientId, clientSecret);
    }

    // Legacy API key support (for migration period)
    const apiKey = request.headers.get("X-API-Key");
    if (apiKey) {
      return await this.validateLegacyApiKey(apiKey);
    }

    throw new AuthError("No valid authentication credentials provided", 401);
  }

  /**
   * Validate Cloudflare Access JWT
   */
  private async validateCloudflareAccess(token: string): Promise<AuthContext> {
    if (!this.env.CF_ACCESS_TEAM_DOMAIN || !this.env.CF_ACCESS_AUD) {
      throw new AuthError("Cloudflare Access not configured", 500);
    }

    try {
      // Create JWKS from team domain
      const JWKS = createRemoteJWKSet(
        new URL(`${this.env.CF_ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`),
      );

      // Verify the JWT
      const { payload } = await jwtVerify(token, JWKS, {
        issuer: this.env.CF_ACCESS_TEAM_DOMAIN,
        audience: this.env.CF_ACCESS_AUD,
      });

      // Extract user information
      return {
        id: payload.sub as string,
        email: payload.email as string,
        name: (payload.name as string) || (payload.email as string),
        type: TokenType.CLOUDFLARE_ACCESS,
        permissions: this.mapGroupsToPermissions(
          (payload.groups as string[]) || [],
        ),
        scopes: ["modules:read", "modules:search"],
        issuedAt: payload.iat!,
        expiresAt: payload.exp!,
        issuer: payload.iss!,
        audience: Array.isArray(payload.aud)
          ? payload.aud
          : [payload.aud as string],
        rateLimitKey: `cf_access:${payload.sub}`,
        groups: (payload.groups as string[]) || [],
        metadata: {
          country: payload.country,
          devicePosture: payload.device_posture,
        },
      };
    } catch (error) {
      throw new AuthError(
        `Invalid Cloudflare Access token: ${error.message}`,
        403,
      );
    }
  }

  /**
   * Validate custom JWT token
   */
  private async validateJWT(token: string): Promise<AuthContext> {
    try {
      let payload;

      // Use public key if available (RS256), otherwise use secret (HS256)
      if (this.env.JWT_PUBLIC_KEY) {
        const publicKey = await importSPKI(this.env.JWT_PUBLIC_KEY, "RS256");
        const result = await jwtVerify(token, publicKey);
        payload = result.payload;
      } else {
        const secret = new TextEncoder().encode(this.env.JWT_SECRET);
        const result = await jwtVerify(token, secret);
        payload = result.payload;
      }

      // Validate and parse payload
      const validatedPayload = JWTPayloadSchema.parse(payload);

      return {
        id: validatedPayload.sub,
        email: validatedPayload.email,
        name: validatedPayload.name,
        type: validatedPayload.type,
        permissions: validatedPayload.permissions,
        scopes: validatedPayload.scopes,
        issuedAt: validatedPayload.iat,
        expiresAt: validatedPayload.exp,
        issuer: validatedPayload.iss,
        audience: Array.isArray(validatedPayload.aud)
          ? validatedPayload.aud
          : validatedPayload.aud
            ? [validatedPayload.aud]
            : undefined,
        rateLimitKey: `jwt:${validatedPayload.sub}`,
        groups: validatedPayload.groups,
        metadata: validatedPayload.metadata,
      };
    } catch (error) {
      throw new AuthError(`Invalid JWT token: ${error.message}`, 403);
    }
  }

  /**
   * Validate service token
   */
  private async validateServiceToken(token: string): Promise<AuthContext> {
    try {
      // Hash the token for comparison
      const tokenHash = await this.hashToken(token);

      // Look up in database
      const result = await this.env.MODULES_DB.prepare(
        `
          SELECT * FROM service_tokens
          WHERE token_hash = ?
          AND (expires_at IS NULL OR expires_at > datetime('now'))
        `,
      )
        .bind(tokenHash)
        .first();

      if (!result) {
        throw new AuthError("Invalid or expired service token", 403);
      }

      const serviceToken = ServiceTokenSchema.parse(result);

      // Update last used timestamp
      await this.env.MODULES_DB.prepare(
        `
          UPDATE service_tokens
          SET last_used = datetime('now')
          WHERE id = ?
        `,
      )
        .bind(serviceToken.id)
        .run();

      return {
        id: serviceToken.id,
        name: serviceToken.name,
        type: TokenType.SERVICE,
        permissions: serviceToken.permissions,
        scopes: serviceToken.scopes,
        issuedAt: Date.parse(serviceToken.created_at) / 1000,
        expiresAt: serviceToken.expires_at
          ? Date.parse(serviceToken.expires_at) / 1000
          : Date.now() / 1000 + 31536000, // 1 year default
        issuer: "nixos-modules-api",
        rateLimitKey: `service:${serviceToken.id}`,
        metadata: serviceToken.metadata,
      };
    } catch (error) {
      throw new AuthError(
        `Service token validation failed: ${error.message}`,
        403,
      );
    }
  }

  /**
   * Validate service credentials (Client ID/Secret pair)
   */
  private async validateServiceCredentials(
    clientId: string,
    clientSecret: string,
  ): Promise<AuthContext> {
    // This could validate against Cloudflare Access service tokens
    // or custom service credentials in the database

    // For Cloudflare Access service tokens
    if (
      this.env.CF_ACCESS_SERVICE_TOKEN_ID === clientId &&
      this.env.CF_ACCESS_SERVICE_TOKEN_SECRET === clientSecret
    ) {
      return {
        id: clientId,
        type: TokenType.SERVICE,
        permissions: [Permission.WRITE, Permission.READ],
        scopes: ["modules:write", "modules:read"],
        issuedAt: Date.now() / 1000,
        expiresAt: Date.now() / 1000 + 3600, // 1 hour
        issuer: "cloudflare-access",
        rateLimitKey: `cf_service:${clientId}`,
      };
    }

    throw new AuthError("Invalid service credentials", 403);
  }

  /**
   * Validate legacy API key (for backwards compatibility)
   */
  private async validateLegacyApiKey(apiKey: string): Promise<AuthContext> {
    // Look up API key in database
    const result = await this.env.MODULES_DB.prepare(
      `
        SELECT * FROM api_keys
        WHERE key_hash = ?
        AND (expires_at IS NULL OR expires_at > datetime('now'))
        AND is_active = 1
      `,
    )
      .bind(await this.hashToken(apiKey))
      .first();

    if (!result) {
      throw new AuthError("Invalid API key", 403);
    }

    // Log deprecation warning
    console.warn(
      `Legacy API key used: ${result.id}. Please migrate to JWT tokens.`,
    );

    return {
      id: result.id as string,
      name: result.name as string,
      type: TokenType.API_KEY,
      permissions: [Permission.WRITE, Permission.READ],
      scopes: ["modules:write", "modules:read"],
      issuedAt: Date.parse(result.created_at as string) / 1000,
      expiresAt: Date.now() / 1000 + 3600, // 1 hour session
      issuer: "legacy-api",
      rateLimitKey: `api_key:${result.id}`,
      metadata: {
        deprecated: true,
        migrateBy: "2025-06-01",
      },
    };
  }

  /**
   * Generate a new JWT token
   */
  async generateToken(
    subject: string,
    claims: Partial<JWTPayloadSchema> = {},
  ): Promise<string> {
    const jwt = new SignJWT({
      ...claims,
      sub: subject,
      type: claims.type || TokenType.USER,
      permissions: claims.permissions || [Permission.READ],
      scopes: claims.scopes || ["modules:read"],
    })
      .setProtectedHeader({ alg: this.env.JWT_PRIVATE_KEY ? "RS256" : "HS256" })
      .setIssuedAt()
      .setIssuer("nixos-modules-api")
      .setExpirationTime("24h");

    // Sign with private key or secret
    if (this.env.JWT_PRIVATE_KEY) {
      const privateKey = await importPKCS8(this.env.JWT_PRIVATE_KEY, "RS256");
      return await jwt.sign(privateKey);
    } else {
      const secret = new TextEncoder().encode(this.env.JWT_SECRET);
      return await jwt.sign(secret);
    }
  }

  /**
   * Create a new service token
   */
  async createServiceToken(
    name: string,
    permissions: Permission[],
    scopes: string[],
    expiresIn?: number,
  ): Promise<{ id: string; token: string }> {
    const id = crypto.randomUUID();
    const token = `st_${this.generateRandomToken(32)}`;
    const tokenHash = await this.hashToken(token);

    const expiresAt = expiresIn
      ? new Date(Date.now() + expiresIn * 1000).toISOString()
      : null;

    await this.env.MODULES_DB.prepare(
      `
        INSERT INTO service_tokens (id, name, token_hash, permissions, scopes, created_at, expires_at)
        VALUES (?, ?, ?, ?, ?, datetime('now'), ?)
      `,
    )
      .bind(
        id,
        name,
        tokenHash,
        JSON.stringify(permissions),
        JSON.stringify(scopes),
        expiresAt,
      )
      .run();

    return { id, token };
  }

  /**
   * Check if user has required permission
   */
  hasPermission(auth: AuthContext, required: Permission): boolean {
    // Super admin has all permissions
    if (auth.permissions.includes(Permission.SUPER_ADMIN)) {
      return true;
    }

    // Admin has all permissions except super admin
    if (
      auth.permissions.includes(Permission.ADMIN) &&
      required !== Permission.SUPER_ADMIN
    ) {
      return true;
    }

    return auth.permissions.includes(required);
  }

  /**
   * Check if user has required scope
   */
  hasScope(auth: AuthContext, required: string): boolean {
    // Check exact match
    if (auth.scopes.includes(required)) {
      return true;
    }

    // Check wildcard scopes (e.g., 'modules:*' matches 'modules:write')
    const requiredParts = required.split(":");
    return auth.scopes.some((scope) => {
      if (scope.endsWith("*")) {
        const scopePrefix = scope.slice(0, -1);
        return required.startsWith(scopePrefix);
      }
      return false;
    });
  }

  /**
   * Apply rate limiting
   */
  async applyRateLimit(
    auth: AuthContext,
    request: Request,
    limitType: "api" | "write" = "api",
  ): Promise<void> {
    const limiter =
      limitType === "write"
        ? this.env.WRITE_RATE_LIMITER
        : this.env.API_RATE_LIMITER;

    const { success, retryAfter } = await limiter.limit(auth.rateLimitKey);

    if (!success) {
      throw new AuthError(
        `Rate limit exceeded. Retry after ${retryAfter} seconds`,
        429,
        { "Retry-After": retryAfter.toString() },
      );
    }
  }

  /**
   * Helper: Map groups to permissions
   */
  private mapGroupsToPermissions(groups: string[]): Permission[] {
    const permissions = new Set<Permission>([Permission.READ]);

    for (const group of groups) {
      switch (group.toLowerCase()) {
        case "admins":
        case "administrators":
          permissions.add(Permission.ADMIN);
          permissions.add(Permission.WRITE);
          break;
        case "maintainers":
        case "editors":
          permissions.add(Permission.WRITE);
          break;
        case "super_admins":
          permissions.add(Permission.SUPER_ADMIN);
          permissions.add(Permission.ADMIN);
          permissions.add(Permission.WRITE);
          break;
      }
    }

    return Array.from(permissions);
  }

  /**
   * Helper: Hash a token
   */
  private async hashToken(token: string): Promise<string> {
    const encoder = new TextEncoder();
    const data = encoder.encode(token);
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  /**
   * Helper: Generate random token
   */
  private generateRandomToken(length: number): string {
    const chars =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const array = new Uint8Array(length);
    crypto.getRandomValues(array);
    return Array.from(array, (byte) => chars[byte % chars.length]).join("");
  }
}

/**
 * Custom authentication error
 */
export class AuthError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public headers: Record<string, string> = {},
  ) {
    super(message);
    this.name = "AuthError";
  }
}

/**
 * Authentication middleware for Hono
 */
export function authMiddleware(requiredPermission?: Permission) {
  return async (c: any, next: any) => {
    try {
      const auth = new Auth(c.env);
      const authContext = await auth.authenticate(c.req.raw);

      // Check permission if required
      if (
        requiredPermission &&
        !auth.hasPermission(authContext, requiredPermission)
      ) {
        return c.json({ error: "Insufficient permissions" }, 403);
      }

      // Apply rate limiting
      await auth.applyRateLimit(authContext, c.req.raw);

      // Add auth context to request
      c.set("auth", authContext);
      c.set("authService", auth);

      await next();
    } catch (error) {
      if (error instanceof AuthError) {
        return c.json(
          { error: error.message },
          error.statusCode,
          error.headers,
        );
      }
      return c.json({ error: "Authentication failed" }, 401);
    }
  };
}
