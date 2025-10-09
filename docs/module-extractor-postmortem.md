# Module Extractor Migration Postmortem

> **Superseded – 2025-10-09:** A derivation-backed exporter (`implementation/module-docs`) now replaces `scripts/extract-nixos-modules.nix` and `scripts/extract-and-upload.sh`. Historical context remains valuable, but new work should reference `docs/module-docs-schema.md`, `docs/module-docs-extraction-plan.md`, and the `module-docs-exporter` CLI described in `docs/configuration-architecture.md` §5.

**Author:** OpenAI Codex (automation helper)
**Date:** 2025-10-09
**Scope:** Attempts to replace the legacy `flake.nixosModules` enumerator inside `scripts/extract-nixos-modules.nix` with a filesystem-driven pipeline that tolerates unresolved imports while passing CI.

---

> **Reviewer (Codex) response – 2025-10-09:** Reviewed this postmortem against the current extractor (`scripts/extract-nixos-modules.nix`), uploader pipeline, and the refreshed guides in `docs/configuration-architecture.md` and `docs/dendritic-pattern-reference.md`. Inline comments below call out what still matches the tree, what drifted, and any follow-up I recommend.

## 1. Background & Expectations

- **Original workflow:** `scripts/extract-nixos-modules.nix` walks `flake.nixosModules` produced by flake-parts/import-tree. It assumes the flake successfully hydrates every module and aborts on missing inputs.
- **New request:** "Teach the enumerator to skip modules whose imports can’t be resolved" and later "Replace the enumerator by scanning `modules/` with import-tree."
- **Constraints:** follow the Agent Operations Guide (no destructive git commands), keep `MODULE_DOCS_EXTRACTION=1` compatibility, avoid editing generated artefacts, and (at the time) maintain the upload script (`scripts/extract-and-upload.sh`, now superseded by `scripts/module-docs-upload.sh`).

> **Reviewer take:** The baseline history lines up with how `collectModules` still sources `flake.nixosModules`, and the safety constraints match the Ops Guide. Two clarifications: (1) the enumerator no longer "aborts" when a module is missing inputs—`processModuleEntry` already `tryEval`s and records a structured failure (see `scripts/extract-nixos-modules.nix:283-360`), so the document should say the abort behavior was historical. (2) `MODULE_DOCS_EXTRACTION` is currently unused across the repo (confirmed via `rg -n MODULE_DOCS_EXTRACTION`), making that compatibility constraint aspirational unless we wire the env var into modules or the extractor. (3) Follow-up work replaced `scripts/extract-and-upload.sh` with `scripts/module-docs-upload.sh`, so future incidents should cite the new derivation-backed pipeline.

## 2. Timeline of Technical Attempts

| Phase | Description                                                                                                          | Outcome                                                                                                                                                           |
| ----- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A     | Added `tryEval` guards around `collectModules` / `processModuleEntry` while still using `flake.nixosModules`         | Failed – evaluation forces `inputs.impermanence` before guards; fatal `attribute 'impermanence' missing`                                                          |
| B     | Stubbed problematic modules (`impermanence`, `dev-cloudflare-sdks`) to short-circuit when `MODULE_DOCS_EXTRACTION=1` | Partial – removed specific crash but discovered additional modules (e.g. `meta/owner.nix`) expecting hydrated flake state                                         |
| C     | Hardened aggregator recursion (depth limit, skip reasons)                                                            | Outcome was 700+ skips, but run still aborted when the same unresolved modules were forced deeper in recursion                                                    |
| D     | Filesystem scan (`builtins.readDir` of `modules/`) + direct imports                                                  | Fatal type conflicts (`flake.nixosModules.base` defined differently across dozens of modules) because flake merges rely on mkMerge semantics                      |
| E     | Flattened each imported file into `{ flake = { nixosModules = ... } }` fragments and rehydrated the attrset          | Produced stack overflows and duplicate merges while recreating the dendritic graph                                                                                |
| F     | Hydrated import-tree module inside extractor (`import-tree ./modules`, evaluate with `lib.evalModules`)              | Equivalent to replaying flake-parts evaluation without guard rails — conflicting option types still triggered (e.g., `sops/default.nix`, `base/nix-settings.nix`) |

> **Reviewer take – timeline:**
>
> - Phase A correctly diagnoses why wrapping `collectModules` in `tryEval` did not help: accessing `flake.nixosModules` still forces attrsets like `inputs.impermanence`. The new `fallbackInputs` block in `scripts/extract-nixos-modules.nix:120-134` now mitigates exactly that failure; consider noting it here.
> - Phase B references `MODULE_DOCS_EXTRACTION`, but those stubs never landed—no module or script branches on that env var today. Readers would benefit from either removing the reference or pointing to the actual fallback attrset that replaced the experiment.
> - Phase C’s recursion hardening is useful background, yet the current `collectModules` short-circuits aggregator attrsets via `isAggregator`/`collectImportEntry`; calling that out would demonstrate how we already reduced the skip explosion.
> - Phases D and E capture why filesystem scanning and reconstructed attrsets failed. Highlight that import-tree already runs once inside `flake.nix`, so replaying it in bash duplicates work and reintroduces those merge conflicts.
> - Phase F’s conclusion aligns with what we now document in `docs/configuration-architecture.md §1`: replaying import-tree + `evalModules` is effectively re-running the flake.

## 3. Root-Cause Insights

1. **Flake-parts merge semantics are required.** Modules like `modules/apps/*.nix` intentionally define overlapping `flake.nixosModules.base` fragments. Without flake-parts’ `mkMerge` ordering, evaluating them ad hoc triggers `conflicting option types`.
2. **Module evaluation needs real `config`.** Several modules reference `config.services`, `config.nix`, or other flake-derived namespaces during their definition phase. Injecting stubs for every field quickly turns into re-implementing host configs.
3. **Import-tree recursion reimports everything.** Calling `import-tree ./modules` inside the extractor duplicates the flake’s module graph. Doing that and then running the legacy enumerator replays the same merges that already fail when done outside the curated flake context.
4. **Stack overflow / infinite recursion** surfaced once `dev-cloudflare-sdks.nix` concatenated `config.flake.nixosModules` while we were rebuilding that attrset at extraction time.

> **Reviewer take – root causes:** Points 1 and 2 match our living guidance in `docs/dendritic-pattern-reference.md` regarding overlapping `flake.nixosModules.*` exports. Point 3 is now partially mitigated because the current collector filters aggregator attrsets before diving deeper, though we still risk duplication if we import raw files; clarifying that nuance would keep the insight current. Point 4 remains valid—`modules/roles/dev-cloudflare-sdks.nix` still folds `config.flake.nixosModules`, so extraction without a full aggregator context will recurse indefinitely.

## 4. Useful Experiments & Diagnostics

- `MODULE_DOCS_EXTRACTION=1 nix eval --show-trace '(import ./scripts/extract-nixos-modules.nix { ... })'` repeated after every change to catch the exact module causing a failure.
- Direct imports such as `nix eval --impure --json '(builtins.getFlake (toString ./. ) ).nixosModules'` confirmed that `flake.nixosModules` already contains attrsets mixing functions and attrsets destined to be merged later.
- Hash comparisons (`sha1sum scripts/extract-and-upload.sh`) validated when we had inadvertently staged earlier normalization patches (subsequently reverted).

> **Reviewer take – diagnostics:** The command cadence is solid, but because `MODULE_DOCS_EXTRACTION` is a no-op today, we should either drop that environment variable from the example or spell out the planned wiring. Consider also pointing readers to `nix develop -c nix repl --expr 'import ./.` (see `docs/configuration-architecture.md §1`) for interactive introspection when a module fails extraction.

## 5. Recommendations Going Forward

1. **Retain the flake-backed enumerator** but let `processModuleEntry` record failures rather than abort (i.e., new `skipReason` path). This isolates problematic modules yet keeps extraction job running.
2. **Add `MODULE_DOCS_EXTRACTION` guards** in modules that require full config context (e.g., `base/*`, `sops/*`, `roles/dev-cloudflare-sdks.nix`). These guards can skip expensive logic or provide deterministic defaults.
3. **Create targeted evaluation tests** under `implementation/nix-tests/` for modules known to rely on inputs. Having unit evaluations ensures future changes keep the docs pipeline compatible.
4. **If filesystem scanning is mandatory**, consider a two-step job: run `nix build .#nixosModulesJSON` (a new derivation exporting flake-derived modules to JSON) and then feed that JSON to the uploader instead of re-evaluating modules in bash.
5. **Document the dendritic pattern contract** (`docs/module-structure-guide.md` already touches on it) and note how module authors can make their files extraction-friendly (e.g., providing guardable metadata default).

> **Reviewer take – recommendations:**
>
> 1. Already in place: `processModuleEntry` (and downstream JSON formatting) now keeps errors in-band. Future work should enrich the `errors` payload with namespaces so the uploader can warn precisely.
> 2. `MODULE_DOCS_EXTRACTION` guards need a clearer contract. Instead of referencing an unused env var, consider codifying a boolean option (for example `config.docExtraction.skip`) or document how to add stubs in `flake.inputs` as done for `impermanence`.
> 3. Fully agree—having `nix eval` checks beside `generation-manager score` will prevent regressions when modules evolve.
> 4. The JSON-export derivation is promising, but please spell out the target output name (e.g. `.nixosModulesJSON`) and who owns it so it can be scheduled.
> 5. This has been delivered: `docs/configuration-architecture.md`, `docs/dendritic-pattern-reference.md`, and the refreshed app/home-manager guides now hold the canonical contract. Cross-linking them here would reduce duplication.

## 6. Key Takeaways

- The repository’s design leverages flake-parts/ import-tree. Untangling that inside a standalone script requires replicating a large chunk of flake-parts logic.
- Missing inputs are less of a problem than option conflicts: once multiple `.nix` files define the same attr path with different types, Nix’s module system halts immediately.
- Attempting to flatten modules per file is not viable without either: (a) strong conventions on how modules export to `flake.nixosModules`, or (b) a precomputed attrset produced by the flake itself.

> **Reviewer take – key takeaways:** Agreed on all three. It may help to note that `moduleBase` now injects a stable `_module.args` scaffolding, which trims some input-missing noise even though the conflicting-option failures still arise.

## 7. Suggested Next Steps for the Team

- Decide whether the deployment pipeline should continue to rely on the flake-evaluated module tree (with improved skip handling) or invest in a new derivation that exports docs-ready JSON.
- If the latter is chosen, schedule a short design session to outline necessary stubs / guard conventions for modules.
- Track future extractor work in an issue referencing this document, so we keep a single source of truth for failure modes.

> **Reviewer take – next steps:** These bullets resonate; adding owners and linking to actual tracking issues (or a backlog section) would make them actionable. Also call out the dev-shell helpers (`write-files`, `gh-actions-run`) introduced in `docs/configuration-architecture.md §5.3` so contributors know which tooling supports the pipeline.

---

_Prepared automatically after reverting all code changes that failed. Feel free to move or edit this document for future planning._

## Reviewer Summary (Codex, 2025-10-09)

- Keep the flake-backed enumerator but update this postmortem to reflect that we now stub missing inputs via `fallbackInputs` and capture failures instead of aborting.
- Drop or clarify `MODULE_DOCS_EXTRACTION` references until we define an actual guard API; otherwise point readers at the documented fallbacks and style guides.
- Focus follow-up on instrumentation (targeted `nix eval` tests and richer skip reporting) and, if desired, scope a derivation that emits JSON for the uploader.
- Align future extractor work with the canonical docs (`docs/configuration-architecture.md`, `docs/dendritic-pattern-reference.md`) and assign owners for modules like `modules/roles/dev-cloudflare-sdks.nix` that still require guard conventions.
