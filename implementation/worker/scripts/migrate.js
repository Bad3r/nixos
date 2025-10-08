#!/usr/bin/env node
/**
 * Database migration runner for D1
 * Applies SQL migrations to the D1 database
 */

const fs = require('fs');
const path = require('path');
const { execSync, execFileSync } = require('child_process');

// Configuration
const MIGRATIONS_DIR = path.join(__dirname, '..', 'migrations');
const DB_NAME = 'nixos-modules-db';
const CF_ACCOUNT_SECRET_PATH = path.resolve(__dirname, '../../..', 'secrets', 'cf-acc-id.yml');
const CF_API_SECRET_PATH = path.resolve(__dirname, '../../..', 'secrets', 'cf-api-token.yml');

const ensureCloudflareAccountId = () => {
  if (process.env.CLOUDFLARE_ACCOUNT_ID) {
    return;
  }

  if (!fs.existsSync(CF_ACCOUNT_SECRET_PATH)) {
    console.warn(`⚠️  Cloudflare account ID secret not found at ${CF_ACCOUNT_SECRET_PATH}. Set CLOUDFLARE_ACCOUNT_ID manually.`);
    return;
  }

  try {
    const accountId = execFileSync('sops', ['-d', '--extract', '["cloudflare_account_id"]', CF_ACCOUNT_SECRET_PATH], {
      encoding: 'utf8'
    }).trim();

    if (accountId) {
      process.env.CLOUDFLARE_ACCOUNT_ID = accountId;
      console.log('🔑 Loaded Cloudflare account ID from SOPS secrets');
    } else {
      console.warn('⚠️  Cloudflare account ID secret is empty');
    }
  } catch (error) {
    console.warn(`⚠️  Failed to load Cloudflare account ID from SOPS: ${error.message}`);
  }
};

const ensureCloudflareApiToken = () => {
  if (process.env.CLOUDFLARE_API_TOKEN) {
    if (!process.env.CF_API_TOKEN) {
      process.env.CF_API_TOKEN = process.env.CLOUDFLARE_API_TOKEN;
    }
    return;
  }

  if (!fs.existsSync(CF_API_SECRET_PATH)) {
    console.warn(`⚠️  Cloudflare API token secret not found at ${CF_API_SECRET_PATH}. Set CLOUDFLARE_API_TOKEN manually.`);
    return;
  }

  try {
    const token = execFileSync('sops', ['-d', '--extract', '["cf_api_token"]', CF_API_SECRET_PATH], {
      encoding: 'utf8'
    }).trim();

    if (token) {
      process.env.CLOUDFLARE_API_TOKEN = token;
      process.env.CF_API_TOKEN = token;
      console.log('🔐 Loaded Cloudflare API token from SOPS secrets');
    } else {
      console.warn('⚠️  Cloudflare API token secret is empty');
    }
  } catch (error) {
    console.warn(`⚠️  Failed to load Cloudflare API token from SOPS: ${error.message}`);
  }
};

// Parse command line arguments
const args = process.argv.slice(2);
const isLocal = args.includes('--local');
const env = args.find(arg => arg.startsWith('--env='))?.split('=')[1];

ensureCloudflareApiToken();
ensureCloudflareAccountId();

console.log('🔄 D1 Database Migration Runner');
console.log('================================');

// Get list of migration files
const getMigrations = () => {
  try {
    const files = fs.readdirSync(MIGRATIONS_DIR);
    return files
      .filter(f => f.endsWith('.sql'))
      .sort() // Ensure migrations run in order
      .map(f => ({
        name: f,
        path: path.join(MIGRATIONS_DIR, f),
        content: fs.readFileSync(path.join(MIGRATIONS_DIR, f), 'utf8')
      }));
  } catch (error) {
    console.error('❌ Failed to read migrations directory:', error.message);
    process.exit(1);
  }
};

// Apply a single migration using wrangler
const applyMigration = (migration, dbName, isLocal, env) => {
  console.log(`📝 Applying migration: ${migration.name}`);

  // Build wrangler command
  let cmd = `npx wrangler d1 execute ${dbName}`;

  if (isLocal) {
    cmd += ' --local';
  }

  if (env) {
    cmd += ` --env ${env}`;
  }

  // Write SQL to temp file (to avoid shell escaping issues)
  const tempFile = `/tmp/migration_${Date.now()}.sql`;
  fs.writeFileSync(tempFile, migration.content);

  try {
    // Execute migration
    cmd += ` --file=${tempFile}`;
    const output = execSync(cmd, { encoding: 'utf8' });

    if (output.includes('error') || output.includes('Error')) {
      console.error(`⚠️  Warning: Migration may have encountered issues`);
      console.error(output);
    } else {
      console.log(`✅ Migration ${migration.name} applied successfully`);
    }
  } catch (error) {
    console.error(`❌ Failed to apply migration ${migration.name}:`, error.message);
    if (error.stdout) {
      console.error('stdout:', error.stdout.toString());
    }
    if (error.stderr) {
      console.error('stderr:', error.stderr.toString());
    }

    // Clean up temp file
    try {
      fs.unlinkSync(tempFile);
    } catch {}

    process.exit(1);
  } finally {
    // Clean up temp file
    try {
      fs.unlinkSync(tempFile);
    } catch {}
  }
};

// Create migrations tracking table (for future use)
const createMigrationsTable = (dbName, isLocal, env) => {
  const sql = `
    CREATE TABLE IF NOT EXISTS migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `;

  let cmd = `npx wrangler d1 execute ${dbName}`;

  if (isLocal) {
    cmd += ' --local';
  }

  if (env) {
    cmd += ` --env ${env}`;
  }

  cmd += ` --command="${sql.replace(/\n/g, ' ').replace(/"/g, '\\"')}"`;

  try {
    execSync(cmd, { encoding: 'utf8' });
    console.log('✅ Migrations tracking table ready');
  } catch (error) {
    console.warn('⚠️  Could not create migrations table (may already exist)');
  }
};

// Main execution
const main = async () => {
  // Determine database name based on environment
  let dbName = DB_NAME;
  if (env === 'staging') {
    dbName = `${DB_NAME}-staging`;
  } else if (env === 'production') {
    dbName = DB_NAME; // Use main database for production
  }

  console.log(`📦 Database: ${dbName}`);
  console.log(`🌍 Environment: ${env || 'development'}`);
  console.log(`💻 Local: ${isLocal ? 'Yes' : 'No'}`);
  console.log('');

  // Create migrations tracking table
  createMigrationsTable(dbName, isLocal, env);
  console.log('');

  // Get and apply migrations
  const migrations = getMigrations();

  if (migrations.length === 0) {
    console.log('📭 No migrations found');
    return;
  }

  console.log(`📋 Found ${migrations.length} migration(s)`);
  console.log('');

  for (const migration of migrations) {
    applyMigration(migration, dbName, isLocal, env);
  }

  console.log('');
  console.log('✨ All migrations completed successfully!');

  // Show database info
  console.log('');
  console.log('📊 Database Information:');

  const infoCmd = `npx wrangler d1 execute ${dbName} --command="SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" ${isLocal ? '--local' : ''} ${env ? `--env ${env}` : ''}`;

  try {
    const tables = execSync(infoCmd, { encoding: 'utf8' });
    console.log('Tables:', tables);
  } catch (error) {
    console.warn('Could not fetch database info');
  }
};

// Run migrations
main().catch(error => {
  console.error('❌ Migration failed:', error);
  process.exit(1);
});
