-- Migration 0002: Seed data for testing
-- This migration is optional and only for development/testing

-- Insert some example modules (only if table is empty)
INSERT INTO modules (path, name, namespace, description, examples, metadata)
SELECT * FROM (
  SELECT
    'modules/base/core.nix' as path,
    'core' as name,
    'base' as namespace,
    'Core system configuration module' as description,
    '["{ services.openssh.enable = true; }", "{ networking.firewall.enable = true; }"]' as examples,
    '{"tags": ["system", "core"], "stability": "stable"}' as metadata
  UNION ALL
  SELECT
    'modules/apps/git.nix',
    'git',
    'apps',
    'Git version control system configuration',
    '["{ programs.git.enable = true; }", "{ programs.git.userName = \"John Doe\"; }"]',
    '{"tags": ["development", "vcs"], "stability": "stable"}'
  UNION ALL
  SELECT
    'modules/workstation/desktop.nix',
    'desktop',
    'workstation',
    'Desktop environment configuration',
    '["{ services.xserver.enable = true; }", "{ services.xserver.displayManager.gdm.enable = true; }"]',
    '{"tags": ["gui", "desktop"], "stability": "stable"}'
  UNION ALL
  SELECT
    'modules/roles/development.nix',
    'development',
    'roles',
    'Development environment role',
    '["{ imports = [ ./base.nix ./apps/git.nix ]; }"]',
    '{"tags": ["role", "development"], "stability": "stable"}'
)
WHERE NOT EXISTS (SELECT 1 FROM modules LIMIT 1);

-- Insert some example options for the core module
INSERT INTO module_options (module_id, name, type, default_value, description, example, read_only, internal)
SELECT
  m.id,
  o.name,
  o.type,
  o.default_value,
  o.description,
  o.example,
  o.read_only,
  o.internal
FROM modules m
CROSS JOIN (
  SELECT
    'enable' as name,
    'boolean' as type,
    'false' as default_value,
    'Whether to enable this module' as description,
    'true' as example,
    0 as read_only,
    0 as internal
  UNION ALL
  SELECT
    'package',
    'package',
    'null',
    'The package to use',
    '"pkgs.git"',
    0,
    0
  UNION ALL
  SELECT
    'extraConfig',
    'lines',
    '""',
    'Extra configuration lines',
    '"alias.st = status\nalias.co = checkout"',
    0,
    0
) o
WHERE m.name = 'core'
  AND NOT EXISTS (SELECT 1 FROM module_options WHERE module_id = m.id LIMIT 1);

-- Insert some example dependencies
INSERT INTO module_dependencies (module_id, depends_on_path, dependency_type)
SELECT
  m.id,
  d.depends_on_path,
  d.dependency_type
FROM modules m
CROSS JOIN (
  SELECT 'modules/base/core.nix' as depends_on_path, 'imports' as dependency_type
  UNION ALL
  SELECT 'modules/apps/git.nix', 'imports'
) d
WHERE m.name = 'development'
  AND NOT EXISTS (SELECT 1 FROM module_dependencies WHERE module_id = m.id LIMIT 1);

-- Insert some example host usage data (with hashed hostnames)
INSERT INTO host_usage (hostname_hash, module_path, first_seen, last_seen)
SELECT * FROM (
  -- SHA256 hash of 'workstation-1'
  SELECT
    'a8c2e9b6d3f1e5c7a9b4d6e8f2c3a7b9d4e6f8a1c3e5b7d9f2a4c6e8b1d3f5e7a9' as hostname_hash,
    'modules/base/core.nix' as module_path,
    datetime('now', '-7 days') as first_seen,
    datetime('now', '-1 hour') as last_seen
  UNION ALL
  SELECT
    'a8c2e9b6d3f1e5c7a9b4d6e8f2c3a7b9d4e6f8a1c3e5b7d9f2a4c6e8b1d3f5e7a9',
    'modules/apps/git.nix',
    datetime('now', '-7 days'),
    datetime('now', '-1 hour')
  UNION ALL
  SELECT
    'a8c2e9b6d3f1e5c7a9b4d6e8f2c3a7b9d4e6f8a1c3e5b7d9f2a4c6e8b1d3f5e7a9',
    'modules/workstation/desktop.nix',
    datetime('now', '-3 days'),
    datetime('now', '-2 hours')
  UNION ALL
  -- SHA256 hash of 'server-1'
  SELECT
    'b7d1f8a4c2e6b9d3f5e7a1c9b3d5e7f9a2c4e6b8d1f3a5c7e9b2d4f6a8c1e3b5d7' as hostname_hash,
    'modules/base/core.nix',
    datetime('now', '-30 days'),
    datetime('now', '-12 hours')
)
WHERE NOT EXISTS (SELECT 1 FROM host_usage LIMIT 1);

-- Note: FTS index will be automatically updated by triggers
-- The FTS table schema was simplified in 0002_fix_fts_schema.sql
-- to only include name, namespace, and description columns