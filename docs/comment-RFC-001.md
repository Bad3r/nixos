# Comments on RFC: Single Source of Truth for App Modules (RFC-001)

## Summary

The RFC proposes moving per-app module registration into a single, typed data source (`flake.lib.nixos.appModules`) and deriving `flake.nixosModules.apps` and role compositions from that source via helpers (`getApp`/`getApps`). The intent is to avoid depending on aggregator internals and to prevent evaluation-order/self-recursion risks.

This review acknowledges the benefits of a centralized registry but identifies several issues with the proposal as written, including a key type mismatch, outdated motivations given our current aggregator schema, and some practical integration concerns. It also suggests a simpler alternative that achieves the RFC’s goals without a full inversion.

## Alignment With Current Architecture

- We now declare explicit, mergeable schemas for both aggregators:
  - `options.flake.nixosModules` with nested `apps = attrsOf deferredModule` and `roles = attrsOf deferredModule` (default `{}`).
  - `options.flake.homeManagerModules` similarly typed.
- Roles are being converged to robust composition patterns (guarded lookups; stable alias modules like `roles.dev`).
- Unknown flake output `modules` was removed; we no longer emit a `modules` output or rely on it.

Given this, the core motivation of the RFC (aggregator flattening/brittleness) is partly outdated: with a typed `apps = attrsOf deferredModule`, nested app modules under `flake.nixosModules.apps.<name>` are stable and discoverable.

## Major Issues

1. Type mismatch in proposed aggregator derivation

- The RFC suggests:
  - `config.flake.nixosModules.apps = { imports = lib.attrValues config.flake.lib.nixos.appModules; };`
- Our current schema defines `apps` as `attrsOf deferredModule`, not a single deferred module. Assigning a single module with `imports` to `apps` violates the declared type and will fail type checking.
- If a bridge is desired, it must mirror each entry individually:
  - Example (pseudo):
    ```nix
    config = lib.mkMerge (
      lib.mapAttrsToList (n: m: {
        flake.nixosModules.apps.${n} = m;
      }) config.flake.lib.nixos.appModules
    );
    ```

2. Motivation is partially outdated

- The brittleness called out (“nested keys become a single module with `imports`”) applies when the aggregator lacks explicit typing for nested namespaces. We now have `apps = attrsOf deferredModule`, so consumers can safely read/write `config.flake.nixosModules.apps.<name>`.
- The robust pattern using `lib.hasAttrByPath`/`lib.getAttrFromPath` against `config.flake.nixosModules.apps` is viable without introducing a new registry.

3. Data vs lib namespace

- The RFC places a data registry under `flake.lib.nixos.*`. In this repo, `flake.lib.*` already carries metadata and HM role data, but it is conceptually “library/options” space.
- Adding a large data registry there is workable but blurs the boundary between functions/library and data. An alternative is to keep the single source “where the modules live” — under the typed `flake.nixosModules.apps` — and implement convenience helpers in `flake.lib.nixos` that operate on `config` rather than duplicating data.

4. Current state mismatch (minor)

- The RFC states roles/media and roles/net have been refactored away from `with config.flake.nixosModules.apps; [...]`. In the repo, `roles/media.nix` still uses `with config.flake.nixosModules.apps` for the apps portion (we only added a guard for optional `media` defaults). A refactor to names+lookups is still pending if we aim for strict robustness.

5. Optional compatibility bridge risks drift

- Maintaining both a registry (`lib.nixos.appModules`) and a mirrored `apps.<name>` risks divergence during migration. This is manageable but needs mechanized checks (e.g., a CI rule to verify 1:1 correspondence during the bridge period).

## Suggested Alternative (Lower Disruption)

- Keep the typed aggregator as the single source of truth for apps:
  - Continue exporting per-app modules to `flake.nixosModules.apps.<name>` (typed: `attrsOf deferredModule`).
  - Add small helpers in `flake.lib.nixos` that operate on `config`:

    ```nix
    config.flake.lib.nixos.getApp = name:
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;

    config.flake.lib.nixos.getApps = names:
      map config.flake.lib.nixos.getApp names;
    ```

  - This preserves the RFC’s ergonomics without introducing a duplicate registry or a migration of all app files.

- Refactor roles to use helpers over strings (no `with`):

  ```nix
  { config, lib, ... }:
  let
    getApp = config.flake.lib.nixos.getApp;
    getApps = config.flake.lib.nixos.getApps;
    names = [ "neovim" "vim" "cmake" ... ];
  in
  {
    flake.nixosModules.roles.dev.imports =
      (getApps names)
      ++ [ config.flake.nixosModules.dev.node ];
  }
  ```

- Add a CI hook to prevent future regressions:
  - e.g., fail if `grep -R "with\s\+config\.flake\.nixosModules\.apps;" modules/roles` matches.

This delivers the RFC intent (stable composition points, helpers, no self recursion) with minimal churn and without type conflicts.

## If Pursuing the RFC’s Inversion

- Define options (as proposed), but fix aggregator derivation to match types:
  - Do not assign `apps = { imports = ...; }`.
  - Mirror entries into `apps.<name>` with `lib.mkMerge (mapAttrsToList ...)`.
- Ensure ordering safety:
  - In flake-parts, options and definitions are merged across modules; setting `config.flake.lib.nixos.appModules.xxx` from app files is safe even if the option is declared in a separate meta module.
- Migration plan refinements:
  - Stage bridge with CI to ensure `appModules` and `apps` remain in sync until the cutover.
  - Provide codemods to rewrite `flake.nixosModules.apps.<name> =` to `flake.lib.nixos.appModules.<name> =` across `modules/apps/*.nix`.

## Minor Comments & Nits

- Naming: `flake.lib.nixos.appModules` is fine but slightly verbose; `flake.lib.nixos.apps` would be shorter and consistent with consumer-facing `nixosModules.apps`.
- Role modules: Good. Keep `flake.nixosModules.roles.dev` consistent with existing usage.
- HM symmetry: Consider adding `flake.lib.homeManager.appModules` in a separate RFC if symmetry is desired. Not required here.
- Examples: Ensure all code examples use string names (e.g., `"neovim"`) rather than relying on lexical scope for clarity and to enforce the no-`with` convention.

## Actionable Outcomes

- Short term (recommended):
  - Add `getApp`/`getApps` in `flake.lib.nixos` as thin helpers over `config.flake.nixosModules.apps`.
  - Refactor roles to strings+helpers; remove `with` usage in roles.
  - Add CI rule preventing reintroduction of `with config.flake.nixosModules.apps` in roles.

- Long term (optional):
  - If the team still prefers a registry inversion, implement it with the corrected `apps.<name>` mirroring to match types, plus a time-boxed bridge and CI checks.

## Conclusion

The RFC’s goals are solid: stable composition, clarity, and independence from aggregator internals. Given our current typed aggregator, we can achieve these goals without inverting the data flow. Introducing `getApp`/`getApps` helpers and tightening role composition patterns provides most of the benefit with far less disruption and avoids the type mismatch outlined above. If we later opt for a registry inversion, we should align the implementation with the aggregator’s declared types to avoid evaluation-time errors.

## Author Response Evaluation (Follow-up)

The author’s response constructively addresses the main concerns and proposes updates to the RFC. A few clarifications and points of disagreement remain:

- Type mismatch concern
  - The response claims our repo does not define a typed nested schema for `flake.nixosModules.apps` and that `apps = { imports = …; }` is valid “today”. This is no longer accurate in `main`: we now explicitly declare `options.flake.nixosModules` with nested `apps = attrsOf deferredModule` and `roles = attrsOf deferredModule` (default `{}`). Under this schema, assigning `apps = { imports = …; }` is not type-correct; each app must be mirrored 1:1. It’s good the RFC will document both patterns, but please align the “current repo” track with the actual schema (mirror entries) to avoid confusion.

- Motivation partially outdated
  - Agreed with the reframing. The immediate brittleness is mitigated via guarded lookups and stable aliases; the single-source inversion remains a strategic improvement, not a required fix.

- Data vs lib namespace
  - Agreement that the low-disruption path (helpers over the existing typed aggregator) is preferable short term. Keeping the inversion as an optional long-term direction with pros/cons called out is reasonable.

- Current state mismatch
  - The response states roles/media and roles/net have been refactored to the robust lookup pattern and given aliases. In the current repo, `roles/media.nix` and `roles/net.nix` still rely on `with config.flake.nixosModules.apps; [...]` for the apps portion and do not define alias modules (`roles.media`, `roles.net`). Please update the RFC status or submit the code changes to reflect this.

- Compatibility bridge drift
  - Agreed. CI invariants to enforce 1:1 mapping during any bridge period are essential.

- Suggested alternative (helpers)
  - Fully aligned. Implement `flake.lib.nixos.getApp/getApps` over `config.flake.nixosModules.apps`, add the CI guard to forbid `with` in roles, and migrate roles to helpers + string names.

- If pursuing inversion
  - The plan to correct the aggregator derivation, enforce CI invariants, provide codemods, and possibly rename to `flake.lib.nixos.apps` addresses the raised concerns. With the current typed schema, the mirroring approach must be used.

Action items to incorporate into the RFC’s “Next Steps”

- Short term
  - Implement `getApp/getApps` in `flake.lib.nixos` and refactor `roles/media.nix` and `roles/net.nix` to helpers + string lists; add alias modules (`roles.media`, `roles.net`).
  - Add a CI rule preventing `with config.flake.nixosModules.apps` in `modules/roles/*`.
- Long term (optional)
  - If adopting inversion, use mirrored entries to respect the typed schema; add CI to keep registry and mirror in sync; time-box the bridge removal.
