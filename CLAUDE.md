# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

NixOS configuration using the **Dendritic Pattern** - automatic module discovery with no manual imports.
- **Hosts**: `system76` (laptop, NVIDIA), `tec` (mini PC, Intel)
- **User**: `vx` (in `modules/meta/owner.nix`)
- **Desktop**: KDE Plasma 6 with Wayland

## Project Structure & Module Organization

- `flake.nix`: Entry point; defines inputs and auto-imports modules via `import-tree`
- `modules/`: NixOS/Home-Manager modules by domain. Files prefixed with `_` are ignored
  - `base/`: Core system (all hosts)
  - `pc/`: Desktop features
  - `workstation/`: Development tools
  - `{system76,tec}/`: Host-specific configs
- `modules/devshell.nix`: Dev tooling (treefmt, pre-commit, LSP)
- `build.sh`: Validation and deployment script (requires permission)
- `nixos_docs_md/`: 460+ local NixOS docs (search here first)

## Development & Validation Commands

```bash
nix develop                                      # Dev shell with tools
nix fmt                                          # Format all files
nix develop -c pre-commit run --all-files       # Run all validation hooks
generation-manager score                         # Dendritic compliance (target: 90/90)
nix flake check --accept-flake-config           # Validate flake

# Safe validation workflow after .nix changes:
./build.sh --dry-run                            # Validate without building
```

## Critical Architecture Rules

1. **No literal path imports** - Use namespace/flake refs only:
   ```nix
   # ❌ NEVER: imports = [ ./foo.nix ];
   # ✅ OK: imports = with config.flake.modules.nixos; [ base pc ];
   ```

2. **Module wrapping** - Only when `pkgs` needed:
   ```nix
   # Needs pkgs - wrap in function:
   { config, lib, ... }:
   {
     flake.modules.nixos.namespace = { pkgs, ... }: {
       environment.systemPackages = [ pkgs.vim ];
     };
   }
   ```

3. **Namespace hierarchy**: `base` → `pc` → `workstation`
4. **Start files with Nix code** - No module headers/comments
5. **Experimental features**: `pipe-operators` required

## Coding Style & Naming

- Nix: 2-space indent; prefer `inherit` and attribute merging
- Modules: lowercase-hyphenated; one concern per file
- Functions: wrap only when `pkgs` required
- Formatting: `nix fmt` must pass before commit

## Testing & Validation

- Warnings treated as errors (`abort-on-warn = true`)
- Pre-commit hooks must pass cleanly
- Dendritic score must be 90/90
- Run validation from repo root

## System Management Commands

```bash
# Safe (no permission needed):
generation-manager list                         # View generations
generation-manager current                      # Show current
generation-manager score                        # Check compliance
git status / git diff                          # View changes

# ⛔ FORBIDDEN without explicit permission:
./build.sh                                      # Build and switch
generation-manager switch/rollback              # Change system
nixos-rebuild / nix build                       # System modifications
sudo nix-collect-garbage                        # Cleanup
```

## Input Branch Management

```bash
# In dev shell:
input-branches-update-all                       # Update all inputs
push-input-branches                             # Push to origin
input-branches-catalog                          # List commands
```

## Commit Guidelines

- Conventional Commits: `feat(scope):`, `fix(module):`, `chore(deps):`
- Sign commits with `-S` flag
- Keep scope small; one logical change per commit

## Security Rules

- **NEVER** run system-modifying commands without permission
- Search `nixos_docs_md/` before online docs
- No secrets/keys in code
- Validate all changes before commit