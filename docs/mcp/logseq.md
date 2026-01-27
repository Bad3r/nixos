# Logseq MCP Server

Official MCP (Model Context Protocol) server for Logseq, enabling AI assistants to interact with your knowledge graph.

> **Note**: Requires Logseq **DB graphs** (database version), not file-based graphs.

## Installation

```bash
npm install -g @logseq/cli
```

## Running the Server

### CLI Command

```bash
logseq mcp-server [options]
```

### Options

| Flag                         | Alias | Default   | Description                              |
| ---------------------------- | ----- | --------- | ---------------------------------------- |
| `--graph <name>`             | `-g`  | -         | Local graph name or sqlite file path     |
| `--api-server-token <token>` | `-a`  | -         | Connect to running Logseq desktop app    |
| `--stdio`                    | `-s`  | false     | Use stdio transport (for Claude Desktop) |
| `--port <num>`               | `-p`  | 12315     | HTTP server port                         |
| `--host <addr>`              | -     | 127.0.0.1 | HTTP server host                         |
| `--debug-tool <name>`        | `-t`  | -         | Debug a specific tool directly           |

### Transport Modes

1. **Streamable HTTP** (default): Starts server on `127.0.0.1:12315`
2. **Stdio** (`-s`): For direct integration with Claude Desktop

## Available Tools

| Tool             | Description                                 | Required Args             |
| ---------------- | ------------------------------------------- | ------------------------- |
| `listPages`      | List all pages in graph                     | `expand` (optional)       |
| `getPage`        | Get page content with blocks                | `pageName` (name or uuid) |
| `listTags`       | List all tags                               | `expand` (optional)       |
| `listProperties` | List all properties                         | `expand` (optional)       |
| `searchBlocks`   | Text search across blocks                   | `searchTerm`              |
| `upsertNodes`    | Create/edit pages, blocks, tags, properties | `operations[]`            |

### upsertNodes Operations

Each operation in the `operations` array must have:

- `operation`: `"add"` or `"edit"`
- `entityType`: `"block"`, `"page"`, `"tag"`, or `"property"`
- `id`: UUID string for edit, temp string for add (if referenced later)
- `data`: Object with entity-specific fields

#### Data Fields by Entity Type

| Entity       | Fields                                                               |
| ------------ | -------------------------------------------------------------------- |
| **page**     | `title`                                                              |
| **block**    | `title`, `page-id` (required), `tags` (uuid array)                   |
| **tag**      | `title`, `class-extends`, `class-properties`                         |
| **property** | `title`, `property-type`, `property-cardinality`, `property-classes` |

## Usage Examples

### Local Graph (HTTP)

```bash
logseq mcp-server -g my-graph
# Server starts on http://127.0.0.1:12315/mcp
```

### Local Graph (Stdio)

```bash
logseq mcp-server -g my-graph -s
```

### Connect to Running Desktop App

```bash
export LOGSEQ_API_SERVER_TOKEN=my-token
logseq mcp-server -a $LOGSEQ_API_SERVER_TOKEN
```

### From Exported SQLite File

```bash
logseq mcp-server -g ~/Downloads/logseq_db_export.sqlite
```

## Integration with Claude

### Claude Desktop Configuration

Add to `~/.config/claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "logseq": {
      "command": "logseq",
      "args": ["mcp-server", "-g", "my-graph", "-s"]
    }
  }
}
```

### Claude Code HTTP Configuration

For HTTP transport, configure in MCP settings:

```json
{
  "mcpServers": {
    "logseq": {
      "type": "http",
      "url": "http://127.0.0.1:12315/mcp",
      "headers": {
        "authorization": "Bearer <your-token>"
      }
    }
  }
}
```

## Testing the Server

### Initialize Session

```bash
curl -sS -X POST "http://127.0.0.1:12315/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "authorization: Bearer <token>" \
  --data-raw '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

Response includes `mcp-session-id` header for subsequent requests.

### List Tools

```bash
curl -sS -X POST "http://127.0.0.1:12315/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "authorization: Bearer <token>" \
  -H "mcp-session-id: <session-id>" \
  --data-raw '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

### Call a Tool

```bash
curl -sS -X POST "http://127.0.0.1:12315/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "authorization: Bearer <token>" \
  -H "mcp-session-id: <session-id>" \
  --data-raw '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"listPages","arguments":{}}}'
```

## Advanced: Direct API Queries

For complex queries not supported by MCP tools, use the underlying HTTP API with Datalog:

### Query Blocks by Tag and Property

```bash
curl -sS -X POST "http://127.0.0.1:12315/api" \
  -H "Content-Type: application/json" \
  -H "authorization: Bearer <token>" \
  --data-raw '{
    "method": "logseq.db.datascriptQuery",
    "args": ["[:find (pull ?b [:block/uuid :block/title {:block/tags [:block/title]} {:user.property/Category [:block/title]}]) :where [?b :block/tags <tag-id>] [?b :user.property/Category <category-id>]]"]
  }'
```

### Get Entity by Name

```bash
curl -sS -X POST "http://127.0.0.1:12315/api" \
  -H "Content-Type: application/json" \
  -H "authorization: Bearer <token>" \
  --data-raw '{"method": "logseq.editor.getPage", "args": ["PageName"]}'
```

### Search Blocks

```bash
curl -sS -X POST "http://127.0.0.1:12315/api" \
  -H "Content-Type: application/json" \
  -H "authorization: Bearer <token>" \
  --data-raw '{"method": "logseq.app.search", "args": ["search term"]}'
```

## Enabling in Logseq Desktop

1. Open Logseq Settings
2. Go to **Advanced**
3. Enable **HTTP APIs Server**
4. Create an authorization token
5. Optionally enable **MCP Server** toggle

## Limitations

- MCP `searchBlocks` is text-based, not tag/property-aware
- Complex queries require direct Datalog via HTTP API
- Only works with DB graphs (not file-based)
- `upsertNodes` doesn't support editing pages/tags/properties yet (only add)

## References

- [Logseq CLI README](https://github.com/logseq/logseq/tree/master/deps/cli)
- [MCP Specification](https://modelcontextprotocol.io/specification/2025-11-25)
- Source: `deps/cli/src/logseq/cli/common/mcp/` in logseq/logseq repo
