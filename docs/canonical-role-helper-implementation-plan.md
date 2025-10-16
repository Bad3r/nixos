# Canonical Role Helper Remediation Plan

## Purpose

Replace the brittle sanitize/flatten pipeline in `modules/meta/nixos-role-helpers.nix`
with a solution that preserves NixOS/Home-Manager metadata, keeps import semantics
intact, and still satisfies RFC-0001’s canonical role requirements (dotted lookup,
alias registry, extras support).

## Task 1 Findings

- **Canonical lookup:** `lib.nixos.roles` must expose dotted canonical identifiers (e.g. `roles.development.core`) via `listRoles`, `getRole`, and friends while evaluating modules through the standard module system (`lib.evalModules` or equivalent). Returned role structures keep the original `imports` list and full attrset, including the `flake.*` subtree, so Home Manager exports survive evaluation.
- **Alias resolution:** Aliases live in the central registry defined by RFC-0001; Phase 0’s alias-resolver guard enforces the mapping. The helper contract therefore includes resolving shorthand names to their canonical targets without mutating metadata, and surfacing failures with actionable errors when an alias is missing.
- **Extras fan-out:** `flake.lib.roleExtras` augments canonical roles with optional modules. The helper must merge these extras into the role output without deduplicating away legitimate entries or stripping attrs, preserving evaluation order and ensuring callers receive extras alongside base imports.
- **Metadata preservation:** Every role ships `metadata.canonicalAppStreamId`, `categories`, `secondaryTags`, and optional `auxiliaryCategories` validated by Phase 0’s metadata lint. The helper cannot sanitize or drop these fields; consumers rely on them for taxonomy checks and documentation generation.
- **Validation hooks:** Required guards remain `nix develop -c treefmt`, `pre-commit`, `nix flake check --accept-flake-config`, the Phase 0 check suite (host-package-guard, profile-purity, alias-registry, taxonomy-version, metadata), the Phase 4 parity build, and the explicit `nix eval .#nixosConfigurations.system76.config.home-manager.users.vx`. Any helper rewrite must leave these checks green and document the commands in change logs.
- **Home Manager contract:** Restoring the System76 regression means ensuring the helper never strips `flake.homeManagerModules.*` (especially `base`), allowing workstation/profile modules to inherit GUI/app bundles. RFC-0001 calls out workstation imports and alias-driven composition that depend on this metadata path staying intact.

## Constraints & Guardrails

- Follow AGENTS.md guardrails (treefmt, pre-commit, flake checks before handing off).
- No destructive git operations; coordinate if unexpected workspace changes appear.
- Prefer built-in module-system primitives (e.g. `lib.evalModules`) over ad-hoc
  recursion. Avoid sanitising away `flake.*` attributes.
- Every task owner **must** start with `sequentialthinking` and reference docs via
  Context7 / deepwiki when unsure about module semantics.

## High-Level Strategy

1. **Design validation:** confirm requirements with RFC-0001 docs and identify the
   minimal data we must expose (role tree, alias map, extras fan-out).
2. **Helper rewrite:** rebuild the role helper around the NixOS module system
   instead of custom flattening. Preserve metadata, but still expose a resolved
   module lookup.
3. **Integration & cleanup:** update callers (Phase 0 guards, roles, profiles) to
   consume the new helper output. Remove obsolete sanitiser utilities.
4. **Regression coverage:** add evaluation checks that assert Home-Manager users
   exist and role extras remain effective.
5. **Documentation & knowledge transfer:** update RFC implementation notes and
   onboarding material to reflect the new helper design.

## Work Breakdown Structure

### Task 1 – Requirements Deep Dive (Owner: Lead Engineer)

- Re-read `docs/RFC-0001/RFC-0001-role-taxonomy-overhaul.md` and
  `docs/RFC-0001/implementation-notes.md` to extract helper expectations.
- Capture mandatory outputs (list of roles, ability to fetch canonical module,
  alias handling, extras injection) in a short design note.
- Deliverable: comment in issue tracker / PR template summarising the precise
  contract.

### Task 2 – Prototype Module Evaluation Wrapper (Owner: Incoming Engineer)

- Build a minimal wrapper that calls `lib.evalModules` (or `evalModules`-like
  primitive) with:
  - Canonical role module
  - Extras modules (from `flake.lib.roleExtras`)
  - Necessary specialArgs (e.g. `inputs`, `nixosAppHelpers`)
- Confirm that the resulting config retains `flake` metadata, imports, and
  Home-Manager exports.
- Deliverable: throwaway Nix expression under `scratch/` or commit draft showing
  evaluation result.

### Task 3 – Implement New Helper (Owner: Incoming Engineer)

- Replace `sanitizeModule`, `sanitizeImportValue`, `flattenImportList`, and the
  bespoke recursion with the wrapper from Task 2.
- Ensure `getRole` returns a structure with:
  - `imports`: original module list (no sanitisation)
  - `metadata`: untouched
  - Additional helper fields (if any) required by RFC (e.g. cached child modules)
- Keep the public API (`lib.nixos.roles.*`) stable where possible; document any
  changes.
- Deliverable: updated `modules/meta/nixos-role-helpers.nix` with focused diffs.

### Task 4 – Update Callers & Guards (Owner: Lead Engineer)

- Adjust Phase 0/Phase 4 checks, workstation profile, and scripts that relied on
  the flattened imports. Remove workaround code that existed only because the old
  helper stripped data (e.g. manual base-module injections).
- Add a new CI check ensuring `nix eval .#nixosConfigurations.system76.config.home-manager.users.vx`
  succeeds.
- Deliverable: green validation suite with updated guard definitions.

### Task 5 – Documentation & Onboarding (Shared)

- Update RFC implementation notes with the new helper strategy.
- Document how aliases/extras work post-refactor.
- Prepare guidance for future engineers about relying on module-system behaviour
  instead of attrset sanitisation.

## Validation Checklist

- `nix develop -c treefmt --fail-on-change`
- `nix develop -c pre-commit run --all-files`
- `nix develop -c nix flake check --accept-flake-config`
- `nix develop -c nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config`
- `nix develop -c nix eval .#nixosConfigurations.system76.config.home-manager.users.vx`
- Manual confirmation: espanso `:test` trigger appears in `~/.config/espanso/match/base.yml`

## Communication & Handover

- Each substantial task is run sequentially; only one major change in flight at a
  time to simplify review.
- Task owners must report back with:
  - Summary of changes
  - Validation results
  - Confidence level and open questions
- Lead engineer reviews and either green-lights the next task or requests fixes.

## Rollback Plan

- If validations fail or regressions surface, revert to last known-good commit on
  `chore/refactor-r1`, re-run the validation checklist, and document findings in
  `docs/postmortem-home-manager-canonical-roles.md`.
