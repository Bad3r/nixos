# Home Manager Bridge Work Summary

## Objective

- Restore `home-manager.users.<owner>` for impacted hosts by letting the canonical Home Manager modules (`flake.homeManagerModules.{base,gui,apps,…}`) flow intact from the role helper through the workstation profile into the System76 host without redefining upstream options.

## Preparation & Baseline Snapshots

- Established collaboration ground rules (every contribution logged via `sequentialthinking`, no tracked code changes without agreement, validations required before sign-off).
- Created scratch helpers:
  - `scratch/hm-flake-prototype.nix` to inspect `lib.meta.nixos.roles.getRole "system.base"` for preserved `flake.homeManagerModules.*`.
  - `scratch/system76-eval.nix` to dump the System76 module import stack with role/host metadata.
- Fixed the prototype path (`builtins.getFlake (toString ../.)`) and wrapped previews in `builtins.tryEval`, producing the baseline snapshot
  `{"hasFlake":false,"hmKeys":[],"importsPreview":{"success":true,"length":169}}`.
- Consultant prepared a validation checklist (role export keys, host import order, duplication guard). Everyone committed to using these artefacts as the “before” reference.

## Sanitiser Iterations

- Initial helper patch retained `flake`/`imports`, but `flattenRoleMap` reattached a synthetic `flake`, leaving `hmKeys` empty and shrinking import lists.
- Subsequent commits (reapplying the logic from commit `95f1ace74` after resets) achieved:
  - `sanitizeModule` preserves `imports`.
  - The raw module’s `flake` subtree is reused (falling back to `config.flake` only when missing).
  - Metadata-aware dedupe prevents duplicate extras.
  - Snapshots now report `{"hasFlake":true,"hmKeys":["apps","base","context7Secrets","gui","r2Secrets"],"importsPreview":{"success":true,"length":174}}`.
- Consultant confirmed the role exports are healthy but noted the host still lacked `home-manager.users.*`.

## Host Wiring & Stylix Dedupe Attempts

- Threaded `_module.args.homeManagerModules` via `lib.mkDefault hmBundle` and prioritised `_module.args` in the bridge before falling back to `config.flake` / `inputs.self`.
- Early host probes still showed duplicate `homeManagerBaseModule` entries and Stylix collisions, so attempts to add option scaffolding were rolled back.
- Multiple baseline resets ensued: each reintroduced minimal wiring, reran probes, and added instrumentation (`originIndex`, `moduleArgsAttrNames`, `configArgs`, `rawImports`).
- The decisive finding: despite the canonical role exporting the bundle, the sanitiser was stripping `flake.homeManagerModules`, so the host never saw it—hence the duplication and missing user tree.

## Latest Discussion Highlights (Replies #1–#36)

- #1 Implementation Owner: Baseline restored; bundle still missing.
- #2 Consultant: Called for full baseline reversion.
- #3 Project Lead: Required validations and documentation for future updates.
- #4 Implementation Owner: Sanitiser still dropping `flake`.
- #5 Consultant & Lead: Ordered reinstatement of commit `95f1ace74`.
- #6 Implementation Owner: `hasFlake = true` for the role, but host still lacks the bundle.
- #7 Project Lead: Emphasised `_module.args` priority and fresh probes.
- #7 Implementation Owner: Host overrides reintroduced; duplication persisted.
- #7 Consultant: Directed reversion to canonical host wiring.
- #13–#19: Iterative probes (baseline, origin indices, raw imports) narrowed the loss point.
- #20 Consultant: Observed `_module.args.homeManagerModules` empty at evaluation.
- #21 Project Lead: Enforced mkDefault wiring and validation guardrail.
- #22–#28 Implementation Owner: Added `moduleArgsAttrNames`, `rawImports`, confirming bundle disappears after sanitisation.
- #31 & #33 Project Lead: Requested deeper instrumentation and canonical role snapshot.
- #35 Implementation Owner: Demonstrated canonical role retains `homeManagerModules`, evaluated config drops it.
- #36 Project Lead: Identified `sanitizeModule` as stripping the `flake` subtree; ordered a helper fix plus fresh probes/validations.

## Reviewer Expectations

- Every code drop must include:
  - `nix develop -c nix eval --impure --accept-flake-config --file scratch/hm-flake-prototype.nix --json` showing `hmKeys` includes `base/gui/apps`.
  - `nix eval --impure --accept-flake-config --file scratch/system76-eval.nix --json` proving the host import stack contains a **single** `homeManagerBaseModule` ahead of extras.
  - Evidence (e.g., jq filter) that `computeImports` did not reintroduce duplicates.
- After probes succeed, run and log the full validation suite (`treefmt`, `pre-commit`, `nix flake check --accept-flake-config`, Phase 4 parity build, Home Manager eval, espanso smoke).

## Current Blockers

1. `modules/meta/nixos-role-helpers.nix::sanitizeModule` still drops the `flake` subtree in some branches, causing `_module.args.homeManagerModules` to be empty during evaluation.
2. Host attempts to compensate (manual imports, helper wrappers) reintroduce duplicate base modules and violate the guardrail.
3. Until the sanitiser fix lands and the host wiring stays minimal, `nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.imports'` cannot succeed, so validations remain blocked.

## Outstanding Actions

- Patch `modules/meta/nixos-role-helpers.nix` so `sanitizeModule` / `flattenRoles` preserve `flake.homeManagerModules`, `flake.nixosModules`, and related metadata.
- Keep `modules/system76/imports.nix` at the minimal wiring: compute `hmBundle` via `lib.recursiveUpdate` and set `_module.args.homeManagerModules` / `flake.homeManagerModules` with `lib.mkDefault`—no direct `getModule "base"`, no manual wrapper imports, no extra `_module.args` fields.
- Maintain the baseline in `modules/home-manager/nixos.nix`; it already pulls from `_module.args.homeManagerModules` once the bundle survives.
- Rerun scratch snapshots and include them with the next reply:
  - `hm-flake-prototype` keys contain `base/gui/apps`.
  - `system76-eval` shows exactly one `homeManagerBaseModule` and populated `configArgs.homeManagerModules`.
  - `nix eval '.#nixosConfigurations.system76.config.home-manager.users.vx.imports' --json` succeeds.
- After probes succeed, execute and log the full validation suite before requesting consultant sign-off.
- Standing protocol: every future code change must commit the discussion update alongside the edits and, once `home-manager.users.<owner>` evaluates, attach the complete validation log.
