# Claude Plugins Technical Reference

The `claude-plugins` project provides extension management infrastructure for Claude Code and other AI coding clients. The project implements two distribution models: **plugins** (Claude Code-specific bundles containing slash commands, agents, and MCP servers) and **skills** (portable SKILL.md files compatible with 15+ AI coding clients).

This document covers the technical architecture, Claude Code integration points, and the `--client claude-code` flag that routes installations to filesystem paths Claude Code discovers at session start.

**Project**: [github.com/Kamalnrf/claude-plugins](https://github.com/Kamalnrf/claude-plugins)
**Registry**: `https://api.claude-plugins.dev`
**Marketplace**: [claude-plugins.dev](https://claude-plugins.dev)
**Status**: Third-party community project (not Anthropic-official)

## Repository Architecture

### Monorepo Structure

Bun-based monorepo with three packages:

```
claude-plugins/
├── package.json                    # Monorepo root, Bun workspaces
├── bun.lock
├── patches/giget@2.0.0.patch       # Patched GitHub downloader
├── skills/
│   └── skills-discovery/SKILL.md   # Meta skill for autonomous discovery
└── packages/
    ├── cli/                        # Plugin manager (claude-plugins)
    │   ├── package.json            # Entry: claude-plugins
    │   └── src/
    │       ├── index.ts            # CLI router
    │       ├── config.ts           # ~/.claude/plugins/config.json management
    │       ├── types/index.ts      # Plugin, Marketplace, Settings types
    │       ├── commands/
    │       │   ├── install.ts      # Plugin installation orchestration
    │       │   ├── list.ts         # List installed plugins
    │       │   ├── enable.ts       # Enable plugin in settings.json
    │       │   ├── disable.ts      # Disable plugin in settings.json
    │       │   └── skills/
    │       │       └── install.ts  # Legacy bridge to skills-installer
    │       ├── core/
    │       │   ├── resolver.ts     # Registry API client
    │       │   ├── plugin.ts       # Metadata extraction
    │       │   ├── marketplace.ts  # Marketplace CRUD
    │       │   └── settings.ts     # Claude Code settings.json integration
    │       └── utils/
    │           ├── fs.ts           # File ops with locking
    │           ├── git.ts          # Git operations
    │           └── validation.ts   # .claude-plugin/ validation
    │
    ├── skills-installer/           # Multi-client skill installer
    │   ├── package.json            # Entry: skills-installer
    │   └── src/
    │       ├── cli.ts              # CLI router with --client flag parser
    │       ├── types.ts            # Skill, Client, Scope types
    │       ├── commands/
    │       │   ├── install.ts      # Skill installation orchestration
    │       │   ├── list.ts         # List installed skills
    │       │   └── search.ts       # Interactive skill search
    │       └── lib/
    │           ├── api.ts          # Registry API v2 client
    │           ├── client-config.ts # CLIENT_CONFIGS mapping
    │           ├── download.ts     # giget wrapper with retry
    │           ├── paths.ts        # Install path computation
    │           ├── select-scope-and-clients.ts # Interactive prompts
    │           └── validate.ts     # SKILL.md validation
    │
    └── web/                        # Astro marketplace frontend
        ├── astro.config.mjs
        └── src/
            ├── pages/
            │   ├── index.astro     # Homepage
            │   ├── skills/         # Skills browser
            │   └── api/            # API endpoints
            └── components/
```

### Tech Stack

| Layer         | Technology                                       |
| ------------- | ------------------------------------------------ |
| Runtime       | Bun (TypeScript execution and package manager)   |
| CLI Framework | @clack/prompts (interactive prompts), picocolors |
| Downloader    | giget (patched for GitHub template downloads)    |
| Web Framework | Astro (static site generation)                   |
| Registry      | Val Town (serverless functions)                  |
| Build         | `bun build` (TypeScript → Node.js bundles)       |

### Package Entry Points

| Package          | Binary Name        | Entry Point                            | Target Runtime |
| ---------------- | ------------------ | -------------------------------------- | -------------- |
| cli              | `claude-plugins`   | `packages/cli/src/index.ts`            | Node.js        |
| skills-installer | `skills-installer` | `packages/skills-installer/src/cli.ts` | Node.js        |
| web              | N/A                | Static site build                      | Browser        |

## Two Extension Models

### Plugins (Claude Code-Specific)

Plugins are Claude Code-specific bundles that can contain:

- **Slash commands**: Custom `/command` invocations
- **Agents**: Specialized subagent configurations
- **MCP servers**: Model Context Protocol integrations

**Required Structure**:

```
plugin-repository/
├── .claude-plugin/
│   ├── marketplace.json    # For marketplace (contains plugins array)
│   └── plugin.json         # For single plugin
├── [plugin content: commands/, agents/, mcp-servers/]
└── [any other files]
```

**Plugin Type Detection** (`packages/cli/src/utils/validation.ts:24-45`):

1. Check for `.claude-plugin/marketplace.json` with `plugins` array → **marketplace**
2. Check for `.claude-plugin/plugin.json` → **single plugin**
3. If neither exists → installation fails

**Marketplace Model**: A marketplace is a repository containing multiple plugins. Each plugin entry specifies:

- `name`: Plugin identifier
- `source`: `{ source: "directory", path: "<absolute-path>" }`
- `description`, `version`, `author`: Metadata
- `commands`, `agents`, `mcpServers`: Capability arrays

**Plugin Metadata Schema**:

```typescript
interface Plugin {
  name: string;
  source: { source: "directory"; path: string };
  description?: string;
  version?: string;
  author?: { name: string; url?: string };
  commands?: string[];
  agents?: string[];
  mcpServers?: string[];
}
```

### Skills (Multi-Client)

Skills are lightweight, portable instructions following the [Agent Skills](https://agentskills.io) standard. A skill is a directory containing a single `SKILL.md` file with YAML frontmatter and Markdown instructions.

**Structure**:

```
skill-repository/
└── SKILL.md              # Required entry point
```

**SKILL.md Format**:

```yaml
---
name: skill-name
description: What this skill does
---
# Skill Title

[Markdown instructions...]
```

Skills are client-agnostic and install to different paths based on the `--client` flag. See [skills.md](skills.md) for complete SKILL.md specification.

## Client Configuration and the `--client` Flag

The `--client` flag (skills-installer only) routes installations to client-specific directories. Each client has a `ClientConfig` defining global and local paths.

### ClientConfig Type

```typescript
interface ClientConfig {
  name: string; // Display name
  globalDir?: string; // User-wide skill directory (e.g., ~/.claude/skills)
  localDir: string; // Project-specific skill directory (e.g., ./.claude/skills)
}
```

### Supported Clients

| Client      | Flag          | Global Directory               | Local Directory       |
| ----------- | ------------- | ------------------------------ | --------------------- |
| Claude Code | `claude-code` | `~/.claude/skills`             | `./.claude/skills`    |
| Cursor      | `cursor`      | ❌ None                        | `./.cursor/skills`    |
| Windsurf    | `windsurf`    | `~/.codeium/windsurf/skills`   | `./.windsurf/skills`  |
| VS Code     | `vscode`      | ❌ None                        | `./.github/skills`    |
| Codex       | `codex`       | `~/.codex/skills`              | `./.codex/skills`     |
| Amp Code    | `amp`         | `~/.config/agents/skills`      | `./.agents/skills`    |
| OpenCode    | `opencode`    | `~/.config/opencode/skill`     | `./.opencode/skill`   |
| Goose       | `goose`       | `~/.config/goose/skills`       | `./.agents/skills`    |
| Letta       | `letta`       | ❌ None                        | `./.skills`           |
| Gemini CLI  | `gemini`      | `~/.gemini/skills`             | `./.gemini/skills`    |
| Antigravity | `antigravity` | `~/.gemini/antigravity/skills` | `./.agent/skills`     |
| Trae        | `trae`        | ❌ None                        | `./.trae/skills`      |
| Qoder       | `qoder`       | `~/.qoder/skills`              | `./.qoder/skills`     |
| CodeBuddy   | `codebuddy`   | `~/.codebuddy/skills`          | `./.codebuddy/skills` |
| GitHub      | `github`      | ❌ None                        | `./.github/skills`    |

**Default Client**: `claude-code`

### Scope Resolution

Skills can install to one of two scopes:

| Scope  | Description                          | Flag                | Fallback Behavior                                |
| ------ | ------------------------------------ | ------------------- | ------------------------------------------------ |
| Global | User-wide (all projects)             | Default             | If `globalDir` undefined, auto-switches to local |
| Local  | Project-specific (current directory) | `--project` or `-p` | Always succeeds (all clients have `localDir`)    |

**Scope Selection Flow** (`packages/skills-installer/src/lib/select-scope-and-clients.ts:103-123`):

1. If `--project` flag present → scope = `local`
2. If `--client` flag present without `--project` → scope = `global`
3. If neither flag → interactive prompt
4. If `globalDir` is undefined and scope is `global` → warn user, switch to `local`

### Flag Flow Through Codebase

```
cli.ts:parseArgs()
  ↓ (extracts flags.client and flags.project)
install.ts:install()
  ↓ (passes { client: string, local: boolean })
select-scope-and-clients.ts:selectScopeAndClients()
  ↓ (validates client via getClientConfig())
  ↓ (resolves scope and filters available clients)
client-config.ts:CLIENT_CONFIGS
  ↓ (returns { name, globalDir?, localDir })
paths.ts:getInstallDir()
  ↓ (computes final filesystem path)
install.ts:installSingleSkill()
  ↓ (writes SKILL.md to computed path)
```

## Claude Code Integration

### Plugin Discovery

Claude Code discovers plugins through two mechanisms:

1. **Known Marketplaces Registry**: `~/.claude/plugins/known_marketplaces.json`
2. **Settings File**: `~/.claude/settings.json` → `enabledPlugins` object

**Known Marketplaces Schema** (`packages/cli/src/core/marketplace.ts:13-29`):

```json
{
  "marketplaces": [
    {
      "name": "marketplace-name",
      "location": "/absolute/path/to/marketplace",
      "plugins": [
        {
          "name": "plugin-name",
          "source": { "source": "directory", "path": "/absolute/path" },
          "description": "...",
          "version": "1.0.0",
          "author": { "name": "..." },
          "commands": ["cmd1"],
          "agents": ["agent1"],
          "mcpServers": ["server1"]
        }
      ]
    }
  ]
}
```

**Settings Schema** (`packages/cli/src/core/settings.ts:4-7`):

```json
{
  "enabledPlugins": {
    "plugin-name@marketplace-name": true,
    "another-plugin@marketplace-name": false
  }
}
```

**Discovery Sequence**:

1. Claude Code session starts
2. Read `~/.claude/plugins/known_marketplaces.json`
3. For each marketplace, read plugin metadata
4. Check `~/.claude/settings.json` → `enabledPlugins` for activation state
5. For enabled plugins, load capabilities from `source.path`

### Skill Discovery

Skills require no registration. Claude Code scans skill directories at session start:

**Global Skills**:

```
~/.claude/skills/
├── skill-one/
│   └── SKILL.md
├── skill-two/
│   └── SKILL.md
└── skill-three/
    └── SKILL.md
```

**Project Skills**:

```
./.claude/skills/
├── project-specific-skill/
│   └── SKILL.md
└── another-skill/
    └── SKILL.md
```

**Discovery Sequence**:

1. Claude Code session starts
2. Scan `~/.claude/skills/*/SKILL.md` (global scope)
3. Scan `./.claude/skills/*/SKILL.md` (project scope, if present)
4. Parse YAML frontmatter for `name`, `description`
5. Load descriptions into semantic index (budget: ~15,000 chars)
6. Full content loads on-demand when skill is invoked

### Filesystem Layout

Complete `.claude/` directory structure managed by claude-plugins:

```
~/.claude/
├── settings.json                      # Claude Code settings
│   └── enabledPlugins                 # Plugin activation state
├── skills/                            # Global skills (managed by skills-installer)
│   ├── skill-name-1/
│   │   └── SKILL.md
│   └── skill-name-2/
│       └── SKILL.md
└── plugins/                           # Plugin system (managed by claude-plugins)
    ├── config.json                    # CLI config (defaultMarketplace, registryUrl)
    ├── known_marketplaces.json        # Marketplace registry
    ├── marketplaces/                  # Cloned plugin repositories
    │   ├── marketplace-name-1/
    │   │   ├── .claude-plugin/
    │   │   │   └── marketplace.json
    │   │   └── [plugin content]
    │   └── marketplace-name-2/
    │       └── ...
    └── cache/                         # Temporary download cache
```

## Installation Flows

### Plugin Installation Flow

Command: `claude-plugins install <plugin-identifier>`

**Step-by-Step Execution** (`packages/cli/src/commands/install.ts:18-121`):

1. **Parse Input**: Extract plugin name from identifier (URL or short-form)
2. **Resolve Plugin**:
   - Call `POST https://api.claude-plugins.dev/api/resolve/<identifier>`
   - Receive `{ gitUrl: "..." }`
   - Error if resolution fails (404 → plugin not in registry)
3. **Clone Repository**:
   - Create temp directory: `~/.claude/plugins/cache/<uuid>`
   - Execute `git clone <gitUrl> <temp-dir>`
   - Error if clone fails (network, permissions, invalid repo)
4. **Validate Structure**:
   - Check for `.claude-plugin/marketplace.json` or `.claude-plugin/plugin.json`
   - Parse JSON and validate schema
   - Error if neither exists or JSON is invalid
5. **Detect Type**:
   - If `marketplace.json` has `plugins` array → marketplace
   - Otherwise → single plugin
6. **Install to Marketplaces Directory**:
   - Move from cache to `~/.claude/plugins/marketplaces/<name>/`
   - Set `source.path` to absolute path for each plugin
7. **Register Marketplace**:
   - Load `~/.claude/plugins/known_marketplaces.json`
   - Add marketplace entry with plugin metadata
   - Write atomically (temp file + rename)
8. **Enable Plugins**:
   - Load `~/.claude/settings.json`
   - Add `enabledPlugins["plugin-name@marketplace-name"] = true` for each plugin
   - Write atomically
9. **Cleanup**:
   - Remove temp directory from cache
10. **Success**: Display installed plugins and paths

**Error Handling**:

- Resolution failure → suggest checking marketplace URL
- Clone failure → display git error, suggest manual clone
- Validation failure → explain required `.claude-plugin/` structure
- All file writes use atomic operations (see Technical Details)

### Skill Installation Flow

Command: `skills-installer install <skill-identifier> [--client <name>] [--project]`

**Step-by-Step Execution** (`packages/skills-installer/src/commands/install.ts:47-186`):

1. **Parse Input**: Extract owner/repo/skill components from identifier
2. **Resolve Skill**:
   - Call `POST https://api.claude-plugins.dev/api/v2/skills/resolve`
   - Body: `{ target: "<identifier>", limit: 10, offset: 0 }`
   - Receive: `{ skills: [...], page: { total, ... } }`
   - Error if no skills found
3. **Select Skill** (if multiple found):
   - Display interactive prompt with skill names, descriptions
   - User selects one skill from list
   - Support pagination if more than 10 results
4. **Validate Client and Scope**:
   - If `--client` flag: validate against `CLIENT_CONFIGS`, error if unknown
   - If `--project` flag: set scope = `local`
   - If client lacks `globalDir` and scope is `global`: warn and switch to `local`
5. **Select Scope and Clients** (if not specified by flags):
   - Prompt: "Select installation scope: Global / Project"
   - Filter clients by scope (remove global-only clients if local selected)
   - Multi-select prompt: "Select client(s) to install for"
   - User can select multiple clients for batch installation
6. **Download Skill** (for each selected client):
   - Normalize GitHub path (strip `/tree/<branch>/`, trailing `/SKILL.md`)
   - Call `giget` with retry logic (3 attempts, exponential backoff)
   - Template: `gh:owner/repo/path` or `gh:owner/repo/path#branch`
   - Download to temp directory
7. **Validate SKILL.md**:
   - Check `SKILL.md` exists in downloaded directory
   - Check file has content (not empty)
   - Error if missing or empty
8. **Install to Target Path**:
   - Compute install path: `<globalDir or localDir>/<skill-name>/`
   - Move from temp to target (overwrite if exists, set `force: true`)
9. **Track Installation** (fire-and-forget):
   - `POST https://api.claude-plugins.dev/api/skills/<owner>/<repo>/<skill>/install`
   - Async, errors logged but not blocking
10. **Success**: Display installed paths and availability scope

**Multi-Client Installation**:

If user selects multiple clients (e.g., `claude-code` + `cursor` + `windsurf`), steps 6-9 repeat for each client with different install paths. All installations complete before success message.

**Error Handling**:

- Resolution failure → suggest checking skill exists at registry
- Download failure after 3 retries → display network error, suggest manual clone
- Validation failure → explain SKILL.md requirement
- Client validation failure → list available clients

## Registry API

The registry is hosted on Val Town and provides resolution, search, and analytics.

**Base URL**: `https://api.claude-plugins.dev`

**Configuration** (`packages/cli/src/config.ts:4-7`):

```typescript
const DEFAULT_CONFIG = {
  defaultMarketplace: "claude-plugin-marketplace",
  registryUrl: "https://api.claude-plugins.dev",
};
```

### Endpoints

#### Plugin Resolution

```
POST /api/resolve/<plugin-identifier>
```

**Request**:

- Path: Plugin identifier (e.g., `anthropics/claude-code-skills`)

**Response**:

```json
{
  "gitUrl": "https://github.com/owner/repo"
}
```

**Error**: `404` if plugin not in registry

#### Skills Resolution (v2)

```
POST /api/v2/skills/resolve
```

**Request**:

```json
{
  "target": "owner/repo/skill",
  "limit": 10,
  "offset": 0
}
```

**Response**:

```json
{
  "status": "success",
  "query": {
    "target": "owner/repo/skill",
    "kind": "specific",
    "normalized": "owner/repo"
  },
  "skills": [
    {
      "namespace": "owner/repo/skill-name",
      "name": "skill-name",
      "relDir": "path/to/skill",
      "sourceUrl": "https://github.com/owner/repo/tree/main/path/to/skill",
      "metadata": {
        "directoryPath": "path/to/skill",
        "description": "...",
        "stars": 100,
        "installs": 50
      }
    }
  ],
  "page": {
    "total": 1,
    "limit": 10,
    "offset": 0
  }
}
```

#### Skills Search

```
GET /api/skills/search?q=<query>&limit=<N>&offset=<N>&orderBy=<field>&order=<asc|desc>
```

**Query Parameters**:

| Parameter | Type   | Default     | Description                                   |
| --------- | ------ | ----------- | --------------------------------------------- |
| `q`       | string | (required)  | Search query                                  |
| `limit`   | number | 10          | Results per page                              |
| `offset`  | number | 0           | Pagination offset                             |
| `orderBy` | string | `relevance` | Sort field: `relevance`, `stars`, `downloads` |
| `order`   | string | `desc`      | Sort direction: `asc`, `desc`                 |

**Response**:

```json
{
  "total": 42,
  "skills": [
    {
      "namespace": "owner/repo/skill-name",
      "name": "skill-name",
      "author": "Author Name",
      "description": "...",
      "stars": 100,
      "installs": 50,
      "sourceUrl": "https://github.com/owner/repo/tree/main/skill",
      "metadata": { "directoryPath": "skill" }
    }
  ]
}
```

#### Installation Analytics

```
POST /api/skills/<owner>/<repo>/<skill-name>/install
```

**Request**: Empty body

**Response**: Status `200` (fire-and-forget, errors ignored)

### Retry Logic

**Download Retry** (`packages/skills-installer/src/lib/download.ts:48-82`):

- Maximum attempts: 3
- Backoff: Exponential (1s, 2s, 4s)
- Implementation:
  ```typescript
  const exponentialBackoff = (attempt: number) =>
    Math.pow(2, attempt - 1) * 1000;
  ```

**API Retry**: No automatic retry at API client level. Errors propagate to CLI for user notification.

## CLI Reference

### claude-plugins

**Installation**: `npm install -g claude-plugins` or `bun install -g claude-plugins`

#### Commands

| Command                              | Description                                   |
| ------------------------------------ | --------------------------------------------- |
| `claude-plugins install <id>`        | Install plugin or marketplace                 |
| `claude-plugins list`                | List installed plugins and marketplaces       |
| `claude-plugins enable <name>`       | Enable a disabled plugin                      |
| `claude-plugins disable <name>`      | Disable an active plugin                      |
| `claude-plugins skills install <id>` | (Legacy) Bridge to `skills-installer install` |

#### Flags

| Flag      | Type    | Default | Description                                    |
| --------- | ------- | ------- | ---------------------------------------------- |
| `--local` | boolean | `false` | (Deprecated) Use with `skills install` command |

#### Examples

```bash
# Install a marketplace
claude-plugins install anthropics/claude-code-plugins

# List installed plugins
claude-plugins list

# Disable a plugin
claude-plugins disable my-plugin@my-marketplace

# Enable a previously disabled plugin
claude-plugins enable my-plugin@my-marketplace
```

### skills-installer

**Installation**: `npm install -g skills-installer` or `bun install -g skills-installer`

#### Commands

| Command                           | Description                               |
| --------------------------------- | ----------------------------------------- |
| `skills-installer search [query]` | Interactive skill search                  |
| `skills-installer install <id>`   | Install skill to selected client(s)       |
| `skills-installer list`           | List installed skills for selected client |

#### Flags

| Flag              | Type    | Default       | Description                                    |
| ----------------- | ------- | ------------- | ---------------------------------------------- |
| `--client <name>` | string  | `claude-code` | Target client (see Client Configuration table) |
| `--project`, `-p` | boolean | `false`       | Install to project directory (local scope)     |
| `--local`, `-l`   | boolean | `false`       | (Deprecated) Alias for `--project`             |

#### Examples

```bash
# Install skill to Claude Code global directory
skills-installer install anthropics/claude-code/commit

# Install to project-local Claude Code directory
skills-installer install anthropics/claude-code/commit --project

# Install to Cursor project directory
skills-installer install anthropics/claude-code/commit --client cursor --project

# Install to multiple clients (interactive)
skills-installer install anthropics/claude-code/commit
# (Prompts for scope, then multi-select for clients)

# Interactive search
skills-installer search frontend
# (Search → select skill → select scope → select clients → install)

# List installed Claude Code skills
skills-installer list

# List installed Cursor skills
skills-installer list --client cursor
```

#### Interactive Search Workflow

The `search` command provides a rich interactive experience:

1. **Query Input**: Enter search term or press Enter to search all
2. **Results Display**: Paginated list with:
   - Skill name (bold)
   - Author
   - GitHub stars and install count
   - Description preview (70 chars)
3. **Actions**:
   - Select skill → proceed to installation
   - Sort results by: Relevance / Most Installs / Most Stars
   - Load more results (if available)
   - New search (enter different query)
   - Exit
4. **Scope Selection**: Global / Project
5. **Client Selection**: Multi-select from available clients
6. **Installation**: Downloads and installs to all selected clients
7. **Next Action**: Search for more / Exit

## Technical Implementation Details

### File Locking

**Problem**: Concurrent writes to JSON files (e.g., multiple `claude-plugins` processes) can corrupt data.

**Solution**: In-memory lock map prevents concurrent modifications to the same file.

**Implementation** (`packages/cli/src/utils/fs.ts:18-47`):

```typescript
const locks = new Map<string, Promise<void>>();

async function withFileLock<T>(
  filePath: string,
  operation: () => Promise<T>,
): Promise<T> {
  // Wait for any existing operation on this file
  while (locks.has(filePath)) {
    await locks.get(filePath);
  }

  // Create new lock
  let releaseLock: () => void;
  const lockPromise = new Promise<void>((resolve) => {
    releaseLock = resolve;
  });
  locks.set(filePath, lockPromise);

  try {
    return await operation();
  } finally {
    locks.delete(filePath);
    releaseLock!();
  }
}
```

All `readJSON` and `writeJSON` operations automatically acquire locks.

### Atomic Writes

**Problem**: Power loss or crash during write can leave JSON files empty or corrupted.

**Solution**: Write to temp file, then atomic rename (POSIX guarantee).

**Implementation** (`packages/cli/src/utils/fs.ts:97-114`):

```typescript
async function writeJSON<T>(filePath: string, data: T): Promise<void> {
  return withFileLock(filePath, async () => {
    const content = JSON.stringify(data, null, 2);
    const tempPath = `${filePath}.tmp`;

    // Write to temp file first
    await writeFile(tempPath, content, "utf-8");

    // Atomic rename (POSIX guarantees atomicity)
    await writeFile(filePath, content, "utf-8");

    // Clean up temp file
    try {
      await rm(tempPath, { force: true });
    } catch {
      // Ignore cleanup errors
    }
  });
}
```

**Note**: This implementation writes twice (once to temp, once to final). A more efficient approach would use `rename()` after the first write.

### GitHub Path Normalization

**Problem**: `giget` (GitHub template downloader) expects specific path formats. User input may include:

- Branch specifiers: `/tree/<branch>/`
- File references: trailing `/SKILL.md`
- Protocol prefixes: `https://`

**Solution**: Normalize before passing to `giget`.

**Implementation** (`packages/skills-installer/src/lib/download.ts:9-31`):

```typescript
const normalizeGithubPath = (
  inputUrl: string,
): { path: string; branch?: string } => {
  const withoutProtocol = inputUrl.replace(/^https?:\/\//i, "");
  const afterHost = withoutProtocol.replace(/^github\.com\/?/i, "");

  // Extract branch if present in /tree/<branch>/ segment
  const branchMatch = afterHost.match(
    /^([^/]+)\/([^/]+)\/tree\/([^/]+)(?:\/(.*))?$/i,
  );
  const branch = branchMatch?.[3];

  // Remove /tree/<branch>/ segment
  const cleaned = afterHost.replace(
    /^([^/]+)\/([^/]+)\/tree\/[^/]+(?:\/(.*))?$/i,
    (_m, owner: string, repo: string, rest?: string) =>
      rest ? `${owner}/${repo}/${rest}` : `${owner}/${repo}`,
  );

  // Strip trailing SKILL.md
  const withoutSkillMd = cleaned.replace(/\/SKILL\.md$/i, "");
  const path = withoutSkillMd.replace(/\/+$/, "");

  return { path, branch };
};
```

**Usage**:

```typescript
const { path, branch } = normalizeGithubPath(sourceUrl);
const template = branch === "master" ? `gh:${path}#${branch}` : `gh:${path}`;
await downloadTemplate(template, { dir: targetPath, force: true });
```

**Special Case**: When default branch is `master`, explicit branch specification (`#master`) is required due to `giget` issue (see [issue #29](https://github.com/Kamalnrf/claude-plugins/issues/29)).

### Validation Pipeline

#### Plugin Validation

**Location**: `packages/cli/src/utils/validation.ts`

**Steps**:

1. Check `.claude-plugin/marketplace.json` exists
2. Parse JSON (catch syntax errors)
3. If `plugins` array exists → marketplace
4. If no `plugins` array, check `.claude-plugin/plugin.json`
5. Validate required fields: `name`, `source`
6. Return type: `"marketplace"` or `"plugin"`

#### Skill Validation

**Location**: `packages/skills-installer/src/lib/validate.ts`

**Steps**:

1. Check `SKILL.md` exists in directory
2. Read file contents
3. Check content length > 0
4. (Optional) Parse YAML frontmatter for `name`, `description`
5. Error if file missing or empty

## Related Documentation

- [Skills Technical Manual](skills.md) — Complete SKILL.md specification and skill system
- [Architecture Documentation](../architecture/) — NixOS module system and configuration patterns
- [MCP Tools Reference](../reference/mcp-tools.md) — Model Context Protocol integrations

## External Resources

- [Claude Plugins Repository](https://github.com/Kamalnrf/claude-plugins) — Source code
- [Claude Plugins Marketplace](https://claude-plugins.dev) — Browse plugins and skills
- [Agent Skills Specification](https://agentskills.io) — Open standard for AI agent skills
- [Claude Code Documentation](https://docs.anthropic.com/claude-code) — Official Claude Code reference
