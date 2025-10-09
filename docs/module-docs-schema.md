# Module Docs Schema

This document tracks the contract emitted by the derivation-backed exporter introduced in October 2025. All downstream consumers (Cloudflare Workers ingestion API, Markdown snapshot publisher, and local tooling) should treat this file as the canonical schema reference. Update it whenever fields are added, renamed, or removed.

## 1. Generated artefacts

| Artefact        | Producer                                                     | Path                              | Notes                                                                                                                    |
| --------------- | ------------------------------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `modules.json`  | `nix build .#moduleDocsBundle` (`packages/module-docs-json`) | `share/module-docs/modules.json`  | Primary JSON payload consumed by the Workers batch API and Markdown renderer.                                            |
| `errors.ndjson` | `packages/module-docs-json`                                  | `share/module-docs/errors.ndjson` | Records extraction failures (status `error`) with namespace, attr path, and error string. Absent when no failures occur. |
| `modules.md`    | `packages/module-docs-markdown`                              | `share/module-docs/modules.md`    | Human-readable inventory that mirrors the JSON `modules` list with status, skip reason, and option counts.               |

## 2. JSON document layout (`modules.json`)

```jsonc
{
  "metadata": {
    "generator": "module-docs-json",
    "system": "x86_64-linux",
    "nixpkgsRevision": "...",
    "flakeRevision": "...",
    "moduleCount": 512,
    "namespaceCount": 2,
  },
  "namespaces": {
    "nixos": {
      "stats": {
        "total": 480,
        "extracted": 472,
        "skipped": 4,
        "failed": 4,
        "extractionRate": 98.3333,
      },
      "modules": [
        {
          "namespace": "nixos",
          "status": "ok", // ok | skipped | error
          "attrPath": ["apps", "codex"],
          "attrPathString": "apps.codex",
          "sourcePath": "modules/apps/codex.nix",
          "skipReason": null,
          "tags": [],
          "meta": {
            "description": "CLI wrapper for OpenAI Codex",
            "skipReason": null,
            "attrPath": "apps.codex",
          },
          "options": {
            "environment.systemPackages": {
              "name": "environment.systemPackages",
              "type": {
                "type": "option-type",
                "name": "listOf",
                "nestedType": { "type": "primitive", "value": "package" },
              },
              "default": null,
              "description": null,
              "declarations": [
                { "file": "modules/apps/codex.nix", "line": 24, "column": 5 },
              ],
            },
          },
          "imports": ["modules/apps/codex.nix"],
          "examples": [],
          "config": {},
        },
      ],
    },
    "home-manager": {
      "stats": {
        "total": 32,
        "extracted": 32,
        "skipped": 0,
        "failed": 0,
        "extractionRate": 100.0,
      },
      "modules": ["…"],
    },
  },
}
```

### Status values

- `ok` – module evaluated successfully and is included in exporter results.
- `skipped` – module set `docExtraction.skip = true;` or `docExtraction.skipReason = "…";`. Options still appear, but ingestion targets may ignore these modules when `skipReason` is non-null.
- `error` – evaluation failed. See `errors.ndjson` for compact copies of these entries. CI (`checks.module-docs`) fails whenever an error entry is produced.

### Option objects

Each entry under `options` inherits the flattened option name for quick lookup. Fields mirror `implementation/module-docs/lib/types.nix`:

| Field                                         | Type               | Description                                                       |
| --------------------------------------------- | ------------------ | ----------------------------------------------------------------- |
| `name`                                        | string             | Fully-qualified option name (`services.test.enable`).             |
| `type`                                        | object             | Structured type metadata (option-type, enum, nested type tree).   |
| `default`, `defaultText`, `example`           | JSON value or null | Values surfaced from module definitions.                          |
| `description`                                 | string or null     | Option description.                                               |
| `readOnly`, `visible`, `internal`, `hasApply` | bool               | Flags carried from the option record.                             |
| `declarations`                                | list               | Each entry includes `file`, `line`, `column`, and optional `url`. |

### Examples list

The exporter records `examples` as `[{ "option": "services.test.users", "example": <value> }]`. Downstream tooling can collate these for documentation snippets or CLI help.

## 3. NDJSON failures (`errors.ndjson`)

Each line is a JSON object containing:

```json
{
  "namespace": "nixos",
  "attrPathString": "roles.dev",
  "error": "Failed to evaluate module: set{...}",
  "sourcePath": "modules/roles/dev.nix"
}
```

Empty file indicates no failures. Cloudflare ingestion jobs can stream this file to alerting sinks without parsing the main bundle.

## 4. Markdown snapshot (`modules.md`)

Markdown is intentionally lightweight for AI retrieval systems. Each namespace becomes a second-level heading, followed by per-module sections:

```
## Namespace nixos
### ✅ apps.codex
- Namespace: nixos
- Source: modules/apps/codex.nix
- Options: 2
```

`⚠️` marks skipped entries (with inline skip reasons) and `❌` marks errors. Editing the Markdown template lives in `implementation/module-docs/derivation-markdown.nix`.

## 5. Maintaining compatibility

1. Update this document and `module-docs-schema.md` when adding or renaming fields.
2. Regenerate bundles locally with `nix run .#module-docs-exporter -- --format json,md --out .cache/module-docs`.
3. For API changes, coordinate with the Workers ingestion service (`implementation/worker`) and refresh fixtures in regression tests once JSON changes land.
4. Keep `checks.module-docs` green by justifying deliberate skips via `docExtraction.skipReason`.

## 6. References

- `implementation/module-docs/graph.nix` – deterministic module traversal and evaluation driver.
- `implementation/module-docs/lib/` – shared type, rendering, and metrics helpers.
- `scripts/module-docs-upload.sh` – optional uploader that batches JSON payloads.
- Local mirrors: `nixos_docs_md/` for module system references and `/home/vx/git/home-manager/docs/manual/writing-modules.md`.
- Context7 snippet for `flake-parts` usage: run `npx -y @upstash/context7-mcp resolve-library-id --name flake-parts` and consult the returned README pointers.
