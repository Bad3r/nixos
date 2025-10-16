# Post-Mortem: Canonical Role Refactor Broke Home‑Manager Integration

## Background

The RFC‑0001 implementation replaces legacy role glue with a canonical taxonomy surfaced through
`modules/meta/nixos-role-helpers.nix`. Hosts such as `system76` now compose their configuration by resolving
canonical roles (e.g. `system.base`, `development.core`) and aggregating their `imports` lists. As part of this
refactor we also expect Home‑Manager to be driven declaratively via the same role pipeline and surfaced through the
workstation profile.

## Environment & Scope

- Host under test: `.#nixosConfigurations.system76`
- Invocation: `nixos-rebuild --accept-flake-config dry-run --flake .#system76 --print-build-logs`
- User profile: `vx` (single owner managed by Home‑Manager)
- Test payload: inject a `:test` trigger into `modules/hm-apps/espanso.nix` and observe whether it lands in
  `~/.config/espanso/match/base.yml`

## Steps to Reproduce

1. Modify `modules/hm-apps/espanso.nix` to add `:test → "[!] test home-manager changes deployed"` to the base match
   list.
2. Run `nixos-rebuild --accept-flake-config dry-run --flake .#system76 --print-build-logs` (no sudo allowed or required).
3. Inspect `$HOME/.config/espanso/match/base.yml` for the new trigger using `rg ':test' ~/.config/espanso/match/base.yml`.
4. Optionally, evaluate `nix eval .#nixosConfigurations.system76.config.home-manager.users.vx` for confirmation.

## Observed Behaviour

- The rebuild reports success and shows the usual activation lines (“switching the user profile of vx”, “activating
  home-manager configuration for vx”).
- The espanso YAML remains unchanged; `rg ':test' ~/.config/espanso/match/base.yml` returns no matches.
- One of the first symptomps is that the base module is not imported in system76's configuration. It is imported into the workstation profile. Its been attempted to add it to system76 imports, which caused duplicate related errors. It has not been attempted yet to remove it from the workstation and add it only to the host system76 to see if that resolves the issue.
- The sanitize/flatten logic is completely flawed. It hides issues, over complicate things, and is not optimal
- The issue is not exclusive to Espanso, its merely used as an example. it affects everything managed by home-manager.

## Expected Behaviour

- `nixos-rebuild` should materialise the owner’s Home‑Manager configuration as part of the switch.
- The espanso match file must contain the new `:test` trigger after the dry-run/switch.
- Evaluating `nixosConfigurations.system76.config.home-manager.users.vx` should yield the merged Home‑Manager option
  tree rather than erroring.

## Technical Root Cause

- Canonical roles are flattened by `computeImports` in `modules/meta/nixos-role-helpers.nix`.
- During the refactor, the helper continued to “sanitise” each module attrset by removing bookkeeping keys before the
  aggregation step.
- The sanitisation accidentally stripped the `flake` subtree, which houses both `flake.nixosModules.base` and
  `flake.homeManagerModules.base`.
- As a result, when `system76` assembled its role set, the base module still contributed `imports`, but the associated
  Home‑Manager module disappeared from the evaluation context.
- Home‑Manager’s top-level module expects `flake.homeManagerModules.base`; without it, option evaluation aborts and the
  declarative user profile is never regenerated despite the rebuild reporting success.

## Secondary Contributing Factors

- The `role-extras-present` CI guard applies modules using a synthetic `{ config = {}; }` stub. That environment also
  lacks the `flake` metadata, so the guard produces false positives/negatives and failed to highlight the missing base
  module.
- No integration assertion verifies that `home-manager.users.<owner>` exists after evaluating the host configuration,
  so the regression went undetected until we manually inspected espanso output.

## Impact Assessment

- Home‑Manager-managed assets (espanso, MCP configuration, shell profiles, etc.) remain frozen.
- Engineers observing successful rebuilds get a false sense of safety because the user profile never updates.

## Current Status

- Modified `modules/hm-apps/espanso.nix` to add `:test → "[!] test home-manager changes deployed"` to the base match list.
- `nix --accept-flake-config eval .#nixosConfigurations.system76.config.home-manager` returns `{ extraAppImports = [ "virt-manager" "bitwarden" "claude-code" "copyq" "discord" "dive" "docker-compose" "dua" "element-desktop" "espanso" "fd" "glow" "feh" "file-roller" "flameshot" "gptfdisk" "keepassxc" "ncdu" "pcmanfm" "ripgrep" "ripgrep-all" "nixvim" "signal-desktop" "skim" "sqlite" "telegram-desktop" "tree" "usbguard-notifier" "zathura" "zoom" ]; }`
- `nix --accept-flake-config eval .#nixosConfigurations.system76.config.home-manager.users` returns the error `error: flake 'git+file:///home/vx/trees/nixos/chore/refactor-r1' does not provide attribute 'packages.x86_64-linux.nixosConfigurations.system76.config.home-manager.users', 'legacyPackages.x86_64-linux.nixosConfigurations.system76.config.home-manager.users' or 'nixosConfigurations.system76.config.home-manager.users'`. The same error is returned for `.#nixosConfigurations.system76.config.home-manager.users.vx`.

## Remediation Plan

1. Update `computeImports` (or an equivalent helper) to preserve the `flake` subtree while de-duplicating extras.
2. Add a smoke test to CI/build scripts: `nix eval .#nixosConfigurations.system76.config.home-manager.users.vx` should
   succeed and expose expected options.
3. Rework `role-extras-present` to interrogate the real host configuration (or another full evaluation) instead of
   synthetic stubs.
4. Document the expectation that canonical roles must surface both `flake.nixosModules.*` and
   `flake.homeManagerModules.*` members; regressions are caught by the new smoke test.
5. Repeat manual validation by applying the espanso trigger and confirming the YAML update after the fixes land.

## Lessons Learned

- Sanitising module attrsets is risky; removing “unused” keys can sever critical metadata paths.
- Unit-style checks must mirror real evaluation contexts to avoid false confidence.
- Always pair structural refactors with observable end-to-end tests (espanso/Nix‑LD activation) to ensure behaviour
  matches expectations.
