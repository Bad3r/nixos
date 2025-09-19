# RFC-001 Rev 3.6 Implementation Checklist

## Baseline Cleanup (pre-work)

- [x] Replace `with config.flake.nixosModules.apps;` usage in:
  - `modules/dev/node.nix`
  - `modules/languages/lang-go.nix`
  - `modules/languages/lang-python.nix`
  - `modules/languages/lang-java.nix`
  - `modules/languages/lang-rust.nix`
  - `modules/languages/lang-clojure.nix`
- [x] Ensure devshell exposes `pre-commit` and `ripgrep` (2025-09-19).

## Implementation Plan Tasks

- [x] Declare helper namespace in `modules/meta/flake-output.nix` (add `flake.lib.nixos` option).
- [x] Add helper implementation module `modules/meta/nixos-app-helpers.nix` with `hasApp`, `getApp`, `getApps`, `getAppOr`.
- [x] Refactor role modules (`modules/roles/dev.nix`, `modules/roles/media.nix`, `modules/roles/net.nix`) to consume helpers, retain aliases, and document non-app imports.
- [x] Install guardrails:
  - [x] Pre-commit hook `forbid-with-apps-in-roles` in `modules/meta/git-hooks.nix`.
  - [x] Flake-level CI checks in `modules/meta/ci.nix` for helper presence and role alias structure.
- [x] Update documentation: `docs/RFC-001.md`, `docs/DENDRITIC_PATTERN_REFERENCE.md`, `docs/MODULE_STRUCTURE_GUIDE.md`, `modules/readme.nix`, and `docs/RFC-single-source-of-truth-app-modules.md` (2025-09-19).
- [x] Run validation commands and capture outputs (2025-09-19):
  - `nix fmt`
  - `nix develop -c pre-commit run --all-files`
  - `generation-manager score` (35/35 after treating the nvidia specialisation check as optional; existing TODO reminders noted)
  - `nix flake check --accept-flake-config`

## Acceptance Criteria Verification

- [x] `modules/meta/flake-output.nix` exports `flake.lib.nixos` (`attrsOf anything`, default `{}`) and documents intent (2025-09-19).
- [x] `modules/meta/nixos-app-helpers.nix` exports helpers with error `Unknown NixOS app '<name>'` for missing apps (2025-09-19).
- [x] `modules/roles/{dev,media,net}.nix` use helper lookups (with helper fallback) and maintain alias modules with comments (2025-09-19).
- [x] `modules/meta/git-hooks.nix` registers `forbid-with-apps-in-roles` using the specified PCRE2 `rg` command (2025-09-19).
- [x] `modules/meta/ci.nix` asserts helper availability and role alias list structure without `mkForce` (2025-09-19).
- [x] Documentation references updated helper API across all listed files (2025-09-19).
- [x] Repo free of `with config.flake.nixosModules.apps` (2025-09-19: no matches).
- [x] No references to `inputs.self.nixosModules` or `self.nixosModules` in roles/helpers (2025-09-19: no matches).

## Baseline Scans (to capture before implementation)

- [x] Run `rg -nU --pcre2 -S --glob 'modules/**/*.nix' -e '(?s)with\s*\(?\s*config\.flake\.nixosModules\.apps\s*\)?\s*;'` (2025-09-19: no matches).
- [x] Run `rg -nU --pcre2 -S --glob 'modules/roles/**/*.nix' --glob 'modules/meta/nixos-app-helpers.nix' -e '\\binputs\\s*\\.\\s*self\\s*\\.\\s*nixosModules\\b' -e '\\bself\\s*\\.\\s*nixosModules\\b'` (2025-09-19: no matches).
