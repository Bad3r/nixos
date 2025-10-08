-- Migration 0004: Authentication tables
-- Creates tables for API keys and service tokens

-- API Keys table (legacy, for backwards compatibility)
CREATE TABLE IF NOT EXISTS api_keys (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  key_hash TEXT UNIQUE NOT NULL,
  permissions TEXT NOT NULL, -- JSON array
  scopes TEXT NOT NULL, -- JSON array
  is_active BOOLEAN DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME,
  last_used DATETIME,
  metadata TEXT -- JSON object
);

CREATE INDEX IF NOT EXISTS idx_api_keys_key_hash ON api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys(is_active);

-- Service Tokens table (modern approach)
CREATE TABLE IF NOT EXISTS service_tokens (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  token_hash TEXT UNIQUE NOT NULL,
  permissions TEXT NOT NULL, -- JSON array
  scopes TEXT NOT NULL, -- JSON array
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME,
  last_used DATETIME,
  metadata TEXT -- JSON object
);

CREATE INDEX IF NOT EXISTS idx_service_tokens_hash ON service_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_service_tokens_expires ON service_tokens(expires_at);

-- Seed a development API key for testing
-- Key: "development-key"
-- SHA-256 hash: a5af5a942743bf1ecbf0be471059478a7210059d98e81ad9ac93d18795d88d43
INSERT INTO api_keys (
  id,
  name,
  key_hash,
  permissions,
  scopes,
  is_active,
  created_at,
  expires_at,
  metadata
) VALUES (
  'dev-key-001',
  'Development API Key',
  'a5af5a942743bf1ecbf0be471059478a7210059d98e81ad9ac93d18795d88d43',
  '["read","write"]',
  '["modules:read","modules:write"]',
  1,
  CURRENT_TIMESTAMP,
  NULL, -- Never expires
  '{"description":"Development and testing key","environment":"development"}'
) ON CONFLICT(id) DO NOTHING;
