# Module Extractor Migration Postmortem

**Author:** OpenAI Codex (automation helper)  
**Date:** 2025-10-09  
**Scope:** Attempts to replace the legacy `flake.nixosModules` enumerator inside `scripts/extract-nixos-modules.nix` with a filesystem-driven pipeline that tolerates unresolved imports while passing CI.

---

## 1. Background & Expectations
- **Original workflow:** `scripts/extract-nixos-modules.nix` walks `flake.nixosModules` produced by flake-parts/import-tree. It assumes the flake successfully hydrates every module and aborts on missing inputs.
- **New request:** "Teach the enumerator to skip modules whose imports can’t be resolved" and later "Replace the enumerator by scanning `modules/` with import-tree."  
- **Constraints:** follow the Agent Operations Guide (no destructive git commands), keep `MODULE_DOCS_EXTRACTION=1` compatibility, avoid editing generated artefacts, and maintain the upload script (`scripts/extract-and-upload.sh`).

## 2. Timeline of Technical Attempts
| Phase | Description | Outcome |
| --- | --- | --- |
| A | Added `tryEval` guards around `collectModules` / `processModuleEntry` while still using `flake.nixosModules` | Failed – evaluation forces `inputs.impermanence` before guards; fatal `attribute 'impermanence' missing` |
| B | Stubbed problematic modules (`impermanence`, `dev-cloudflare-sdks`) to short-circuit when `MODULE_DOCS_EXTRACTION=1` | Partial – removed specific crash but discovered additional modules (e.g. `meta/owner.nix`) expecting hydrated flake state |
| C | Hardened aggregator recursion (depth limit, skip reasons) | Outcome was 700+ skips, but run still aborted when the same unresolved modules were forced deeper in recursion |
| D | Filesystem scan (`builtins.readDir` of `modules/`) + direct imports | Fatal type conflicts (`flake.nixosModules.base` defined differently across dozens of modules) because flake merges rely on mkMerge semantics |
| E | Flattened each imported file into `{ flake = { nixosModules = ... } }` fragments and rehydrated the attrset | Produced stack overflows and duplicate merges while recreating the dendritic graph |
| F | Hydrated import-tree module inside extractor (`import-tree ./modules`, evaluate with `lib.evalModules`) | Equivalent to replaying flake-parts evaluation without guard rails — conflicting option types still triggered (e.g., `sops/default.nix`, `base/nix-settings.nix`)

## 3. Root-Cause Insights
1. **Flake-parts merge semantics are required.** Modules like `modules/apps/*.nix` intentionally define overlapping `flake.nixosModules.base` fragments. Without flake-parts’ `mkMerge` ordering, evaluating them ad hoc triggers `conflicting option types`.
2. **Module evaluation needs real `config`.** Several modules reference `config.services`, `config.nix`, or other flake-derived namespaces during their definition phase. Injecting stubs for every field quickly turns into re-implementing host configs.
3. **Import-tree recursion reimports everything.** Calling `import-tree ./modules` inside the extractor duplicates the flake’s module graph. Doing that and then running the legacy enumerator replays the same merges that already fail when done outside the curated flake context.
4. **Stack overflow / infinite recursion** surfaced once `dev-cloudflare-sdks.nix` concatenated `config.flake.nixosModules` while we were rebuilding that attrset at extraction time.

## 4. Useful Experiments & Diagnostics
- `MODULE_DOCS_EXTRACTION=1 nix eval --show-trace '(import ./scripts/extract-nixos-modules.nix { ... })'` repeated after every change to catch the exact module causing a failure.
- Direct imports such as `nix eval --impure --json '(builtins.getFlake (toString ./. ) ).nixosModules'` confirmed that `flake.nixosModules` already contains attrsets mixing functions and attrsets destined to be merged later.
- Hash comparisons (`sha1sum scripts/extract-and-upload.sh`) validated when we had inadvertently staged earlier normalization patches (subsequently reverted).

## 5. Recommendations Going Forward
1. **Retain the flake-backed enumerator** but let `processModuleEntry` record failures rather than abort (i.e., new `skipReason` path). This isolates problematic modules yet keeps extraction job running.
2. **Add `MODULE_DOCS_EXTRACTION` guards** in modules that require full config context (e.g., `base/*`, `sops/*`, `roles/dev-cloudflare-sdks.nix`). These guards can skip expensive logic or provide deterministic defaults.
3. **Create targeted evaluation tests** under `implementation/nix-tests/` for modules known to rely on inputs. Having unit evaluations ensures future changes keep the docs pipeline compatible.
4. **If filesystem scanning is mandatory**, consider a two-step job: run `nix build .#nixosModulesJSON` (a new derivation exporting flake-derived modules to JSON) and then feed that JSON to the uploader instead of re-evaluating modules in bash.
5. **Document the dendritic pattern contract** (`docs/module-structure-guide.md` already touches on it) and note how module authors can make their files extraction-friendly (e.g., providing guardable metadata default).

## 6. Key Takeaways
- The repository’s design leverages flake-parts/ import-tree. Untangling that inside a standalone script requires replicating a large chunk of flake-parts logic.
- Missing inputs are less of a problem than option conflicts: once multiple `.nix` files define the same attr path with different types, Nix’s module system halts immediately.
- Attempting to flatten modules per file is not viable without either: (a) strong conventions on how modules export to `flake.nixosModules`, or (b) a precomputed attrset produced by the flake itself.

## 7. Suggested Next Steps for the Team
- Decide whether the deployment pipeline should continue to rely on the flake-evaluated module tree (with improved skip handling) or invest in a new derivation that exports docs-ready JSON.
- If the latter is chosen, schedule a short design session to outline necessary stubs / guard conventions for modules.
- Track future extractor work in an issue referencing this document, so we keep a single source of truth for failure modes.

---

*Prepared automatically after reverting all code changes that failed. Feel free to move or edit this document for future planning.*
