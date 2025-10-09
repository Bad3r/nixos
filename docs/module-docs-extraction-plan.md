# Module Docs Extraction Rebuild Plan

**Author:** Codex (GPT-5)
**Date:** 2025-10-09
**Status:** ✅ Implemented via `implementation/module-docs/*`, `packages/module-docs-*`, and `scripts/module-docs-upload.sh`. Continue to extend this plan when adding new exporters or schema revisions.
**Scope:** Replace the legacy `scripts/extract-nixos-modules.nix` + `scripts/extract-and-upload.sh` flow with a derivation-backed documentation exporter that is resilient to aggregator fan-out, honors the dendritic pattern, and emits machine/reader-ready assets without historical compatibility constraints.

---

## 1. Objectives & Success Metrics

- **Single-source derivation:** Produce a `nix build .#moduleDocsBundle` output (JSON + Markdown) without invoking ad-hoc `nix eval` or bash-driven loops.
- **Deterministic module graph:** Evaluate every entry reachable from `flake.nixosModules` and `flake.homeManagerModules`, surfacing unresolved imports as structured diagnostics rather than impure crashes.
- **Schema clarity:** Emit a documented JSON schema (`docs/module-docs-schema.md`) and Markdown indices so API consumers and editors can reason about changes easily.
- **Runtime budget:** Keep full extraction (evaluation + JSON + Markdown render) ≤ 90s on dev hardware and ≤ 3m in CI when using binary caches.
- **Observability:** Capture run metadata (timestamp, nixpkgs revision, extraction rate, list of skipped modules with root-cause tags) for dashboards.

## 2. Current-State Findings (Condensed)

| Pain Point             | Evidence                                                                                     | Impact                                                                         |
| ---------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Impure `nix eval` path | `scripts/extract-and-upload.sh` shells `nix eval --impure`                                   | Breaks in sandboxed CI; depends on user PATH for `jq`, `node`                  |
| Partial guard rails    | `scripts/extract-nixos-modules.nix` has `fallbackInputs` but no module-level suppression API | Hard to keep noisy roles (e.g. `roles/dev-cloudflare-sdks.nix`) from thrashing |
| Aggregator replay      | Collector walks `flake.nixosModules` attrsets and rescans aggregator branches                | Duplicate evaluation + confusing skip totals                                   |
| JSON post-process      | Node-based Markdown generator reruns serialization, diverging from JSON payload              | Adds maintenance overhead                                                      |

Supporting docs consulted: repo `docs/configuration-architecture.md` (§§1–3), `docs/dendritic-pattern-reference.md`, plus module system guidance from `nixos_docs_md/455_portable_service_options.md` (specialArgs) and Home Manager’s `docs/manual/writing-modules.md`.

## 3. Target Architecture

```
flake.nix
 └─ outputs.moduleDocsBundle
      ├─ pkg:module-docs-json      # derivation producing structured JSON
      ├─ pkg:module-docs-markdown  # derivation producing filtered Markdown snapshots
      └─ checks.module-docs        # CI check piping metrics into evaluation logs
```

### 3.1 Module Graph Stage

- Build `implementation/module-graph.nix` that imports the flake via `flake-parts.lib.mkFlake { inherit inputs; }` (see `/hercules-ci/flake-parts` guidance pulled via Context7) and reuses the repository’s `flake.inputs` plus a constrained `withSystem` adapter.
- Evaluate modules with `lib.evalModules` once per namespace (`nixos`, `homeManager`), passing a curated `specialArgs` derived from the NixOS manual (cf. `nixos_docs_md/455_portable_service_options.md` discussion of `_module.args`/`specialArgs`).
- Introduce a `docExtraction.skipReason` option (boolean + freeform string) so modules opt out deliberately; default to `false` to maintain coverage.

### 3.2 Extraction Library Stage

- Refactor `implementation/lib/extract-modules.nix` into:
  1. `lib/module-extract/types.nix` – pure utilities for option/type flattening.
  2. `lib/module-extract/render.nix` – JSON/Markdown formatting, deduping declarations, linking to source paths.
  3. `lib/module-extract/metrics.nix` – aggregator for stats, skip tags, per-namespace module counts.
- Inputs: evaluated module (attrset), module metadata (path, namespace, docExtraction flags).
- Outputs: normalized module doc record with `options`, `imports`, `examples`, `meta` (mirrors existing JSON but adds `skipReason`, `originSystem`).

### 3.3 Derivation & CLI Stage

- Add `packages/module-docs-json` exposing `pkgs.callPackage ./implementation/module-docs-derivation.nix { }`. The derivation should:
  - Evaluate both module graphs (NixOS + Home Manager) using cached `flake` inputs.
  - Emit `result/share/module-docs/modules.json`.
  - Emit `result/share/module-docs/errors.ndjson` for quick CLI consumption.
- Add `packages/module-docs-markdown` that renders Markdown via a `json2md` Nix script (avoid Node if possible; otherwise vendor a small `deno` or `pandoc` pipeline pinned in the derivation).
- Provide a thin CLI wrapper `apps.module-docs-exporter` (bash or `nix run`) to copy outputs to `.cache/module-docs/` and optionally upload.

### 3.4 Upload Path Integration

- Replace `scripts/extract-and-upload.sh` with `scripts/module-docs-upload.sh` that:
  1. Invokes `nix run .#module-docs-exporter -- --format json,md --out .cache/module-docs`.
  2. Streams `modules.json` to the API, chunking via `jq -c '.modules[]'` (available from derivation’s runtime closure).
  3. Publishes Markdown snapshots to Workers R2 (if desired) using the existing API key env vars.
- Document helper commands in `docs/configuration-architecture.md` and `docs/module-extractor-postmortem.md` once implementation lands.

## 4. Implementation Phases & Tasks

### Phase 0 – Foundations (2 engineer-days)

- [ ] Inventory `flake.nixosModules` / `flake.homeManagerModules` namespaces via `nix repl` to confirm canonical roots.
- [ ] Draft the `docExtraction.skipReason` option in `modules/meta/docs.nix`; ensure it defaults to `null`.
- [ ] Update developer docs for new targets (append to `docs/module-structure-guide.md`).

### Phase 1 – Module Graph Builder (4 engineer-days)

- [ ] Author `implementation/module-graph.nix` with inputs `(flakeRoot, systems, specialArgsExtra)`.
- [ ] Reuse `withSystem` helpers by referencing `docs/configuration-architecture.md §1.1` guidance on aggregator wiring.
- [ ] Validate module graph by running `nix eval .#moduleGraphPreview --json | jq '.stats'`.

### Phase 2 – Extraction Library Refactor (3 engineer-days)

- [ ] Split extraction helpers into `{types,render,metrics}.nix`; add unit tests under `implementation/tests/` using `nix eval`.
- [ ] Support `skipReason` and `originSystem` fields, tagging modules flagged during Phase 0.
- [ ] Ensure `extractExamples` de-duplicates options that share declarations.

### Phase 3 – Derivation Packaging (3 engineer-days)

- [ ] Create `packages/module-docs-json/default.nix`; wire into `flake.nix` `packages` output.
- [ ] Mirror for Markdown exporter; include `treefmt` rules if templates emit Markdown.
- [ ] Register `apps.module-docs-exporter` for `nix run` convenience.

### Phase 4 – CLI & Upload Rewrite (2 engineer-days)

- [ ] Replace `scripts/extract-and-upload.sh` with new script; support `--dry-run` and `--format` flags.
- [ ] Update CI (GitHub Actions) to run `nix build .#moduleDocsBundle` and publish artifacts.
- [ ] Capture upload metrics using the same schema as `scripts/extract-and-upload.sh` (but sourced from JSON metadata).

### Phase 5 – Documentation & Enablement (2 engineer-days)

- [ ] Refresh `docs/configuration-architecture.md` tooling section to list the new derivation and CLI.
- [ ] Update `docs/module-extractor-postmortem.md` with a “superseded” note and link to this plan once work starts.
- [ ] Author `docs/module-docs-schema.md` describing JSON structure, Markdown layout, and skip semantics.

### Phase 6 – Validation & Rollout (ongoing)

- [ ] Add `checks.module-docs` that runs `nix run .#module-docs-exporter -- --check` and fails on skips without `skipReason`.
- [ ] Smoke-test against cached systems `x86_64-linux` and `aarch64-darwin` (mirrors `modules/systems.nix`).
- [ ] Coordinate with API consumers to validate ingest of the new schema before cutting over.

## 5. Testing & Diagnostics

| Area                    | Command                                                     | Notes                                                         |
| ----------------------- | ----------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------- |
| Module graph validation | `nix eval .#moduleGraphPreview --json`                      | Ensure aggregator fan-out resolves without conflicting types. |
| JSON schema lint        | `nix develop -c jq --slurpfile schema schema.json '.modules | map(has("options"))'`                                         | Derivation should expose schema file. |
| Markdown diff           | `nix develop -c treefmt`                                    | Use existing formatter for deterministic markdown.            |
| Upload dry-run          | `scripts/module-docs-upload.sh --dry-run --format json`     | Confirms CLI + API pipeline.                                  |

Manual references leveraged:

- `nixos_docs_md/455_portable_service_options.md` – `specialArgs` rationale for passing custom args during module evaluation.
- `/git/github.com/nix-community/home-manager/docs/manual/writing-modules.md` – affirms Home Manager shares the NixOS module system, so shared extraction logic applies.
- Context7 `/hercules-ci/flake-parts` snippets – highlight recommended `flake-parts.lib.mkFlake { inherit inputs; }` usage for the new derivation root.

## 6. Risks & Mitigations

| Risk                                   | Mitigation                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Long evaluation time on macOS builders | Cache `moduleDocsBundle` in CI and gate via per-system subsets (`systems = ["x86_64-linux" "aarch64-darwin"]`).     |
| Modules lacking guard rails            | Enforce `docExtraction.skipReason` check in `checks.module-docs`; escalate findings to module owners.               |
| Toolchain drift (jq/node)              | Favor pure Nix derivations; if external tooling is unavoidable, bundle via Nixpkgs packages pinned in `flake.lock`. |
| API consumers expecting legacy schema  | Publish schema + changelog beforehand; provide sample JSON files for consumers to test.                             |

## 7. Deliverables Checklist

- [ ] `implementation/module-graph.nix` & refactored extraction library.
- [ ] `packages/module-docs-json`, `packages/module-docs-markdown`, `apps.module-docs-exporter`.
- [ ] `scripts/module-docs-upload.sh` replacement.
- [ ] Updated docs (`configuration-architecture`, `module-structure-guide`, new schema doc, postmortem note).
- [ ] CI wiring (`checks.module-docs`, GitHub Action step) and release notes entry.

---

_Ready for implementation. Update this plan as milestones complete so future contributors inherit accurate context._
