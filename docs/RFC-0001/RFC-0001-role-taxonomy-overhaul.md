# RFC-0001: Role Taxonomy Overhaul

## Status

- **Draft:** 1.0.0
- **Created:** 2025-10-12

## Summary

We will replace the ad-hoc list of `roles.<name>` bundles with a hierarchical taxonomy that mirrors the Freedesktop AppStream category registry. The new structure will make host composition predictable, reduce overlap between roles, and scale as more applications are added. The migration happens in one cutover: existing hosts (e.g., `system76`) will immediately consume the new roles/profiles with identical behaviour—no transitional modules or grace periods are maintained; only explicit convenience aliases (e.g., `roles.dev`) point to their canonical targets.

## Motivation

- Current names (`files`, `file-sharing`, `dev`, `media`, etc.) have overlapping scopes and no consistent hierarchy.
- Adding new roles requires guesswork and often duplicates existing bundles.
- Implementation in this branch targets a single cutover—keeping the old and new structures in parallel would introduce churn without benefit, so the design assumes no transitional compatibility layer.
- A future-proof taxonomy should:
  1. Reuse industry-standard categories to minimize bikeshedding.
  2. Allow usage of sub‑roles to narrow down to specific toolsets (e.g., `system.storage.backup`).
  3. Keep the number of top-level buckets small enough for humans to reason about.

For new contributors, the lack of structure has translated into trial-and-error: role names rarely hint at whether they ship desktop apps, CLIs, or vendor packages, and onboarding requires diffing existing hosts to understand what “dev” versus “development.workspace.core” contains. Formalising the taxonomy gives newcomers a discoverable map that matches familiar desktop categories while still covering workstation-specific tooling.

## Prior Art

- **Freedesktop/AppStream** defines standardized desktop categories used by GNOME Software, KDE Discover, and many distro stores. It provides a concise set of top-level categories (AudioVideo, Development, Education, Game, Graphics, Network, Office, Science, System, Utility) with optional subcategories such as `System;FileTools;` or `Utility;Compression;`. ([category registry](https://specifications.freedesktop.org/menu-spec/latest/category-registry.html))

Freedesktop already ships with nixpkgs metadata, so the new taxonomy simply adopts those category roots and subcategories without introducing any parallel classification systems. CLI-first workloads map cleanly as well: language toolchains sit under `Development`, base system services and security hardening under `System`, and small utilities under `Utility`.

## Proposal

### Taxonomy

- Adopt the Freedesktop/AppStream root categories verbatim (`AudioVideo`, `Development`, `Education`, `Game`, `Graphics`, `Network`, `Office`, `Science`, `System`, `Utility`).
- Canonical role identifiers follow the pattern `roles.<root-slug>.<subrole?>`, where `<root-slug>` is the lowercase, hyphenated form of the AppStream root (e.g., `AudioVideo` → `audio-video`).
- Keep the namespace shallow (three segments maximum, counting any vendor suffix). Specialised modules (e.g., language LSP bundles) extend their parent via imports instead of creating a fourth segment.
- Parent roles remain thin aggregators: a host importing `roles.game` implicitly receives the default gaming subroles listed in the category matrix below, so a workstation has launchers without enumerating them manually.
- Provide ergonomic aliases that permanently resolve to canonical roles (e.g., `roles.dev`, `roles.dev.python`, `roles.dev.py`). Aliases are maintained in a central registry so renaming a canonical role only requires updating the registry; shorthand imports remain stable.

| AppStream root | Canonical namespace prefix | Core subrole families (examples)                                          | Notes                                                                                       |
| -------------- | -------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| AudioVideo     | `roles.audio-video`        | `media`, `production`, `streaming`                                        | Covers multimedia playback/creation, including CLI utilities surfaced by desktop launchers. |
| Development    | `roles.development`        | `core`, `python`, `go`, `rust`, `clojure`, `ai`                           | Language bundles, debuggers, and shared tooling all live here.                              |
| Education      | `roles.education`          | `research`, `learning-tools`                                              | Reserved for future study suites; currently empty but scaffolded.                           |
| Game           | `roles.game`               | `launchers`, `tools`, `emulation`                                         | `roles.game` aggregates the launchers subrole by default.                                   |
| Graphics       | `roles.graphics`           | `illustration`, `cad`, `photography`                                      | Includes creative tooling and vendor-specific art assets.                                   |
| Network        | `roles.network`            | `sharing`, `tools`, `remote-access`, `vendor.<name>`                      | Vendor glue (e.g., Cloudflare) nests under `vendor` to stay within the depth constraint.    |
| Office         | `roles.office`             | `productivity`, `planning`                                                | Productivity suites and accessories.                                                        |
| Science        | `roles.science`            | `data`, `visualisation`                                                   | Placeholder for lab tooling; intentionally optional.                                        |
| System         | `roles.system`             | `base`, `display.x11`, `storage`, `security`, `vendor.<name>`, `prospect` | System services, base stack, and workstation bundle live here.                              |
| Utility        | `roles.utility`            | `cli`, `archive`, `monitoring`                                            | General-purpose CLI helpers outside the System base.                                        |

The matrix doubles as validation input for the taxonomy helper library introduced in Phase 1 (`lib/taxonomy/matrix.nix`), keeping documentation and enforcement in sync.

Deeper specialisations stay within the three-segment limit by modelling variants as module options or nested imports inside the canonical subrole. For example, `roles.development.python` exposes feature flags for `frameworks.django` and `lsp.pyright` rather than creating `roles.development.python.frameworks.django`. If multiple variants warrant their own bundles, they register as sibling subroles (e.g., `roles.development.python-web`) and reuse the existing alias family (`roles.dev.python.web`) via the central registry. Cross-cutting concerns (backup that touches `System` and `Network`) are expressed through composition: the canonical role lives under the primary root, while `auxiliaryCategories`, `secondaryTags`, and curated profiles keep the discoverability story intact without exploding alias counts.

### Role Metadata

- Every role publishes

  ```nix
  metadata = {
    canonicalAppStreamId = "System"; # literal entry from the registry
    categories = [ "System" "Settings" ];
    secondaryTags = [ "hardware-integration" ];
  };
  ```

  `canonicalAppStreamId` must be an exact root (or officially recognised subcategory) from the Freedesktop registry, while `categories` captures the semicolon-separated `Categories=` string emitted by upstream desktop files. When upstream metadata is missing (e.g., custom System76 wallpapers), the helper library provides a curated allowlist and validation routine so local overrides remain compliant.

- Subcategories are implicit in the `categories` list; language bundles or other specialised stacks must include the AppStream subcategory that justifies their scope (`Development`, `Development;IDE;`, `System;Security;`, etc.).
- `secondaryTags` remain repository-specific hints surfaced in documentation/search; they are restricted to a controlled vocabulary maintained alongside the alias registry. When a role genuinely spans domains, it may also provide `auxiliaryCategories` (drawn from the same AppStream registry) purely for documentation and search—tooling still treats the canonical root as the source of truth.
- Commands for extracting AppStream categories from nixpkgs packages (and other implementation details) live in `docs/RFC-0001/implementation-notes.md`.
- The helper library ships with a generated snapshot of the upstream AppStream registry plus a small `metadata-overrides.json` file for packages that lack `.desktop` data. Phase 0 checks ensure `canonicalAppStreamId` is always present in `categories` (or the override list) so the two fields cannot drift; if they disagree, the metadata lint fails and points to the offending role.

### Development Bundles

- Shared editor/debugger tooling moves into `roles.development.core` (Neovim, VS Code FHS shell, `gdb`, `valgrind`, `jq`, etc.).
- Each language bundle (e.g., `roles.development.python`) includes the runtime/interpreter, a package manager, formatter/linter defaults, and optional adapters (debuggers, LSP servers):

  ```nix
  roles.development.python = {
    runtime = [ pkgs.python313 pkgs.uv ];
    formatters = [ pkgs.ruff ];
    linters = [ pkgs.pyright pkgs.ruff ];
    debuggers = [ pkgs.debugpy ];
  };
  ```

  (Pseudo-code for illustration.) Multiple language bundles can be composed alongside `roles.development.core` without duplication. Alias mappings (`roles.dev`, `roles.dev.python`, `roles.dev.py`, …) must resolve to these canonical roles.

### Vendor Bundles

- Vendor- or fleet-specific roles live under `roles.<category>.vendor.<name>` (e.g., `roles.system.vendor.system76`).
- These bundles declare the same metadata schema and import vendor-specific modules only. A template implementation and module snippets are documented in `docs/RFC-0001/implementation-notes.md`.

### Profiles

- Profiles (`profiles.<name>`) provide opinionated compositions of roles for common deployment archetypes. `profiles.workstation` composes the generic desktop/development roles enumerated in the implementation notes; host- or vendor-specific layers remain in host configuration.
- Additional profiles (e.g., VPS, macOS integration, edge gateway) follow the same pattern and remain optional starting points.

#### Reference Role: `roles.system.prospect`

- Captures the full workstation package surface of the current System76 host so the migration can prove parity in Phase 4.
- Treated as a `System`-root role with the `prospect` subrole in the taxonomy matrix above.
- Detailed metadata, sample module scaffolding for vendor roles, and the manifest JSON (`workstation-packages.json`) reside in `docs/RFC-0001/implementation-notes.md` to keep the RFC focused on design intent.

#### Profiles namespace (legacy `workstation` migration)

- Roles stay granular; _profiles_ are curated compositions that string multiple roles together for a deployment archetype (developer workstation, VPS, etc.).
- Create `profiles.<name>` under `flake.nixosModules.profiles` and migrate the existing `workstation` bundle into `profiles.workstation`. It imports the generic desktop/development roles enumerated in the implementation notes; host- or vendor-specific layers remain in host configuration.
- Document the concept in `docs/configuration-architecture.md` and the RFC: profiles are “one import” starting points, not replacements for explicit role selection.
- Anticipated follow-up profiles:
  - `profiles.vps`: headless server baseline combining `roles.system.backup`, `roles.network.remote-access`, `roles.system.security`.
  - `profiles.macos-integration`: tooling for macOS fleet bootstrap (cross-platform dev kits, zero-trust agents).
  - `profiles.edge-gateway`: networking appliance stack mixing `roles.network.firewall`, `roles.system.monitoring`, vendor-specific add-ons.
- Profiles are optional: they provide a launchpad that can later be decomposed into explicit roles as requirements diverge.

## Migration Plan

### Phase 0 – Test & Guardrail Baseline

- Add failing-but-actionable checks before refactoring:
  - `checks/phase0/host-package-guard.sh`, surfaced via `nix build .#checks.x86_64-linux.phase0-host-package-guard --accept-flake-config`, asserts that `environment.systemPackages` on every host (currently only `system76`) matches an allowlisted set generated from `roles.system.prospect`.
  - `checks/phase0/profile-purity.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-profile-purity --accept-flake-config`, evaluates `profiles.workstation` and fails if it declares packages or options outside `roles.*` imports.
  - `checks/phase0/alias-resolver.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-alias-registry --accept-flake-config`, iterates the alias map and ensures each entry resolves to the canonical module path described in the taxonomy matrix.
  - `checks/phase0/taxonomy-version.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-taxonomy-version --accept-flake-config`, recomputes `TAXONOMY_VERSION` from the alias registry hash and fails if the constant is outdated.
  - `checks/phase0/metadata-lint.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-metadata --accept-flake-config`, verifies every role provides `canonicalAppStreamId`, `categories`, `secondaryTags`, and optional `auxiliaryCategories` values that pass the helper validation against the Freedesktop registry.
  - `scripts/list-role-imports.py`, surfaced via `nix build .#checks.x86_64-linux.phase0-role-imports --accept-flake-config`, ensures the reporter continues to parse modules correctly (CI uses the `--offline` mode).
- CI and local workflows must call `nix flake check --accept-flake-config` so these checks block merges; failing checks are addressed before starting Phase 1.
- **Exit criteria:** new checks are committed, wired into CI, and currently highlight the gaps that the subsequent phases will close.

### Phase 1 – Discovery & Tooling

- Generate a complete inventory of legacy `roles.*` modules and their package contents.
- Produce helper scripts/lints that verify AppStream metadata (`canonicalAppStreamId`, `categories`, `secondaryTags`, `auxiliaryCategories`) and report gaps.
- **Exit criteria:** scripts run cleanly against the current tree; lint rules are in place (even if initially failing) so subsequent phases surface omissions immediately.

### Phase 2 – Canonical Role Refactor

- Create the new taxonomy directories and rewrite each legacy role into its Freedesktop-aligned counterpart (`roles.system.storage`, `roles.utility.archive`, `roles.development.core`, `roles.development.python`, etc.).
- Register the canonical alias map (`roles.dev`, `roles.dev.py`, `roles.sys`, …) so shorthands resolve through a single lookup; update the map rather than the code when renaming canonical namespaces.
- Remove the legacy role entry points in the same commits to avoid divergent code paths.
- **Exit criteria:** running the lint suite shows every role exposes metadata, the alias map resolves without collisions, and no modules load the old role files.

### Phase 3 – Workstation Profile Cutover

- Build the new `profiles.workstation` using only taxonomy roles listed in the implementation notes; exclude vendor/host specifics from the profile itself.
- Update `configurations.nixos.system76` (and any other consumers) to import the profile plus any host-specific vendor roles.
- **Exit criteria:** evaluating the `profiles.workstation` flake attribute (e.g., `nix eval .#profiles.workstation` or `nix build .#profiles.workstation`) succeeds, and the old workstation aggregation module is retired.

### Phase 4 – Parity Validation & Docs

- Capture before/after manifests for `environment.systemPackages` (e.g., `nix eval … --json`) and store the JSON in `docs/RFC-0001/workstation-packages.json`. A companion check (`nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config`) compares the JSON to the live evaluation so drift is detected automatically.
- Run `nix fmt`, the new tests from Phase 0, `nix flake check`, and targeted `nix eval` assertions to prove user-facing tools (`notify-send`, `prettier`, etc.) remain available.
- Update documentation (`docs/configuration-architecture.md`, release notes, alias listings) to reflect the new taxonomy and profile entry points.
- **Exit criteria:** parity diffs show no regressions, all formatting/tests (including Phase 0 guards) pass, and documentation changes are committed alongside the code updates.

## Alternatives Considered

- **Custom taxonomy per team:** Rejected; this repo is maintained by a single operator, and duplicating effort provides zero benefit. Freedesktop coverage plus secondary tags already captures CLI tooling, language stacks, and bespoke bundles like `roles.system.prospect` without inventing new roots.
- **Leaning entirely on package attributes:** Roles provide curated bundles; simply tagging packages would lose that composition layer.
- **Inventing a brand-new classification from scratch:** Overkill. Freedesktop/AppStream already matches the needs of the workstation and keeps us aligned with existing nixpkgs metadata while still allowing explicit documentation of any internal extensions.

## Open Questions

- Should we allow roles to belong to multiple categories (e.g., `Network` + `Utility`)? Initial stance: no; each role keeps a single canonical root, while optional `secondaryTags` and a documented `auxiliaryCategories` list (used only for docs/search) cover genuine cross-domain cases such as backup tools that touch storage and security. We will revisit the stance once two or more roles require duplicate canonical homes or when contributors report discoverability gaps even with `auxiliaryCategories`. Until then, composition guidelines and profile documentation describe how to surface multi-domain bundles in search tooling.
- Do we want host profiles to import an entire category at once (`roles.system._all`)? Could be added later.
- How do we version the taxonomy to avoid breakage? `TAXONOMY_VERSION` lives in the taxonomy helper library and is defined as `<major>.<minor>` where `major` increments when canonical role paths change and `minor` increments when aliases or metadata vocabularies change. Phase 0 adds a check (`nix build .#checks.x86_64-linux.phase0-taxonomy-version --accept-flake-config`) that recomputes the version from the alias registry hash so the constant cannot drift.

## Implementation Checklist

Key execution requirements:

- Phase 0 guardrails (`checks/phase0/*`) must land before any refactor: host package allowlist, profile purity, alias registry, taxonomy-version, and metadata lint all wired into `nix flake check --accept-flake-config`.
- The alias registry (documented in the implementation notes) is the single source of truth for shorthands such as `roles.dev.py`; every rename updates the registry and the Phase 0 alias resolver.
- Parity proof hinges on `roles.system.prospect` and the recorded manifest (`docs/RFC-0001/workstation-packages.json`). Phase 4’s `.#checks.phase4.workstation-parity` compares the JSON with a live `nix eval` to guarantee the cutover preserves user-facing packages.
- Rollbacks follow the play described in Phase 4: if parity fails, revert to the last Phase 2 commit, refresh the manifest, and make the tests pass again before proceeding.

Detailed scripts, metadata override files, and workstation role inventories remain in `docs/RFC-0001/implementation-notes.md`.

## References

- [Freedesktop AppStream category registry](https://specifications.freedesktop.org/menu-spec/latest/category-registry.html)
