-- Migration 0001: Initial schema for NixOS Module Documentation API
-- This creates the core tables and indexes for the MVP implementation

-- Drop existing tables if they exist (for clean migration)
DROP TABLE IF EXISTS modules_fts;
DROP TABLE IF EXISTS host_usage;
DROP TABLE IF EXISTS module_dependencies;
DROP TABLE IF EXISTS module_options;
DROP TABLE IF EXISTS modules;

-- Modules table: Core module information
CREATE TABLE modules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  namespace TEXT NOT NULL,
  description TEXT,
  examples TEXT, -- JSON array of example configurations
  metadata TEXT, -- JSON object for additional metadata
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for efficient querying
CREATE INDEX idx_modules_namespace ON modules(namespace);
CREATE INDEX idx_modules_name ON modules(name);
CREATE UNIQUE INDEX idx_modules_namespace_name ON modules(namespace, name);
CREATE INDEX idx_modules_updated_at ON modules(updated_at DESC);

-- Module options table: Configuration options for each module
CREATE TABLE module_options (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  module_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  default_value TEXT, -- JSON value
  description TEXT,
  example TEXT, -- JSON value
  read_only BOOLEAN DEFAULT 0,
  internal BOOLEAN DEFAULT 0,
  FOREIGN KEY (module_id) REFERENCES modules(id) ON DELETE CASCADE
);

-- Index for efficient option lookups
CREATE INDEX idx_module_options_module_id ON module_options(module_id);
CREATE INDEX idx_module_options_name ON module_options(name);

-- Module dependencies table: Track module import relationships
CREATE TABLE module_dependencies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  module_id INTEGER NOT NULL,
  depends_on_path TEXT NOT NULL,
  dependency_type TEXT DEFAULT 'imports',
  FOREIGN KEY (module_id) REFERENCES modules(id) ON DELETE CASCADE
);

-- Indexes for dependency graph traversal
CREATE INDEX idx_module_dependencies_module_id ON module_dependencies(module_id);
CREATE INDEX idx_module_dependencies_depends_on ON module_dependencies(depends_on_path);

-- Host usage table: Track which modules are used by which hosts
CREATE TABLE host_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hostname_hash TEXT NOT NULL, -- SHA256 hash for privacy
  module_path TEXT NOT NULL,
  first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(hostname_hash, module_path)
);

-- Indexes for usage analytics
CREATE INDEX idx_host_usage_hostname ON host_usage(hostname_hash);
CREATE INDEX idx_host_usage_module_path ON host_usage(module_path);
CREATE INDEX idx_host_usage_last_seen ON host_usage(last_seen DESC);

-- FTS5 virtual table for full-text search
CREATE VIRTUAL TABLE modules_fts USING fts5(
  name,
  namespace,
  description,
  option_names,
  option_descriptions,
  content=modules,
  content_rowid=id,
  tokenize='porter unicode61'
);

-- Triggers to keep FTS index in sync with modules table
CREATE TRIGGER modules_ai AFTER INSERT ON modules BEGIN
  INSERT INTO modules_fts(rowid, name, namespace, description)
  VALUES (new.id, new.name, new.namespace, new.description);
END;

CREATE TRIGGER modules_ad AFTER DELETE ON modules BEGIN
  DELETE FROM modules_fts WHERE rowid = old.id;
END;

CREATE TRIGGER modules_au AFTER UPDATE ON modules BEGIN
  UPDATE modules_fts
  SET name = new.name,
      namespace = new.namespace,
      description = new.description
  WHERE rowid = new.id;
END;

-- Trigger to update the updated_at timestamp
CREATE TRIGGER modules_update_timestamp AFTER UPDATE ON modules BEGIN
  UPDATE modules SET updated_at = CURRENT_TIMESTAMP WHERE id = new.id;
END;

-- View for common module queries with usage count
CREATE VIEW modules_with_usage AS
SELECT
  m.*,
  COUNT(DISTINCT hu.hostname_hash) as usage_count
FROM modules m
LEFT JOIN host_usage hu ON m.path = hu.module_path
GROUP BY m.id;

-- View for namespace statistics
CREATE VIEW namespace_stats AS
SELECT
  namespace,
  COUNT(*) as module_count,
  COUNT(DISTINCT hu.hostname_hash) as host_count
FROM modules m
LEFT JOIN host_usage hu ON m.path = hu.module_path
GROUP BY namespace
ORDER BY module_count DESC;