# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Reference

**Validate changes (ALWAYS run after modifying .nix files):**
```bash
# Run all pre-commit hooks
nix develop -c pre-commit run --all-files

# Quick format check
nix fmt

# Full validation suite
nix develop -c pre-commit run --all-files && \
generation-manager score && \
nix flake check --accept-flake-config && \
nixos-rebuild build --flake .#$(hostname)
```

**Build system (⚠️ ONLY when user explicitly requests):**
```bash
# Build and switch configuration (system-wide changes!)
./build.sh

# Build with optimizations (recommended)
./build.sh --collect-garbage --optimize --offline

# Build for specific host
./build.sh --host tec  # or system76

# Dry-run build (safe - no system changes)
nixos-rebuild build --flake .#$(hostname)
```

## Repository Overview

This is a NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery. Based on the golden standard from `mightyiam/infra`.

### System Information

- **Hosts**:
  - `system76` - System76 laptop with NVIDIA GPU, LUKS encryption, Btrfs filesystem
  - `tec` - GMKtec K7 Plus mini PC with Intel graphics, LUKS encryption, ext4 filesystem (current host)
- **User**: `vx` (defined in `modules/meta/owner.nix`)
- **Desktop**: KDE Plasma 6 with Wayland
- **Architecture**: x86_64-linux

### Documentation Sources

⚠️ **IMPORTANT**: Always use local documentation first:

1. **Local NixOS docs** (`nixos_docs_md/` - 460+ files):
   ```bash
   # Search local docs FIRST for NixOS questions
   grep -r "postgresql" nixos_docs_md/
   grep -r "networking\." nixos_docs_md/
   ls nixos_docs_md/ | grep -i service_name
   ```

2. **Dendritic Pattern docs** (`docs/` directory):
   - `NIXOS_CONFIGURATION_REVIEW_CHECKLIST.md` - Systematic review checklist
   - `DENDRITIC_PATTERN_*.md` - Pattern documentation
   - `RECOVERY_GUIDE.md` - System recovery procedures

3. **System docs**:
   ```bash
   man configuration.nix
   man home-configuration.nix
   nixos-help  # Opens full manual in browser
   ```

## Critical Architecture Rules

### Dendritic Pattern Requirements

1. **No explicit imports** - Modules auto-discovered by import-tree
2. **No module headers** - Start directly with Nix code
3. **Namespace hierarchy**: `base` → `pc` → `workstation`
4. **Function wrapping** - Only when module needs `pkgs`:
   ```nix
   # Needs pkgs - wrap in function:
   { config, lib, ... }:
   {
     flake.modules.nixos.namespace = { pkgs, ... }: {
       environment.systemPackages = [ pkgs.vim ];
     };
   }

   # No pkgs needed - direct configuration:
   { config, lib, ... }:
   {
     flake.modules.nixos.namespace = {
       services.openssh.enable = true;
     };
   }
   ```
5. **Experimental features required**: `pipe-operators` must be enabled
6. **abort-on-warn = true** - Enforced for clean builds

### Host Configuration Pattern

- Hosts use: `configurations.nixos.<hostname>.module`
- Entry points: `modules/{system76,tec}/imports.nix`
- Each host imports appropriate namespace chain

## Essential Commands

### Development & Validation

```bash
# Enter development shell
nix develop

# Format all Nix files
nix fmt

# Run pre-commit hooks (formatting, dead code, anti-patterns)
nix develop -c pre-commit run --all-files

# Check Dendritic Pattern compliance (should be 100/100)
generation-manager score

# Validate flake
nix flake check --accept-flake-config

# Update flake inputs
nix flake update
nix flake update nixpkgs home-manager  # Specific inputs

# Check what would change
nixos-rebuild build --flake .#$(hostname)
nix-diff $(readlink /run/current-system) result
```

### System Management

```bash
# Generation management
generation-manager list               # List all generations
generation-manager current            # Show current generation
generation-manager clean 5            # Keep only last 5
generation-manager switch <host>      # Switch to host config
generation-manager rollback [N]       # Rollback N generations
generation-manager diff <g1> <g2>     # Compare generations

# Emergency rollback
sudo nixos-rebuild switch --rollback

# Garbage collection
sudo nix-collect-garbage -d          # Remove old generations
nix-store --optimise                  # Deduplicate store files
```

### Code Quality Workflow

After ANY changes to .nix files:

```bash
# Step 1: Identify issues
nix develop -c pre-commit run --all-files

# Step 2: If issues found, create fix plan using TodoWrite tool

# Step 3: Fix systematically
nix develop -c pre-commit run nixfmt-rfc-style --all-files  # Format
nix develop -c pre-commit run deadnix --all-files           # Dead code
nix develop -c pre-commit run statix --all-files            # Anti-patterns

# Step 4: Final validation
nix develop -c pre-commit run --all-files  # Must pass cleanly
```

## Pre-commit Hooks

Automatically run on git commit:
- `nixfmt-rfc-style` - Nix formatting
- `deadnix` - Dead code detection
- `statix` - Anti-pattern linting
- `flake-checker` - Flake validation
- `shellcheck` - Shell script linting
- `typos` - Typo detection
- `ripsecrets` - Secret scanning
- `detect-private-keys` - Private key detection
- `check-json` / `check-yaml` - Config validation
- `trim-trailing-whitespace` - Whitespace cleanup

## Module Organization

### Directory Structure

```
modules/
├── meta/               # Owner info, generation-manager
├── base/               # Core system (all hosts)
├── pc/                 # Desktop features
├── workstation/        # Development tools
├── system76/           # System76 host modules
├── tec/                # GMKtec host modules
├── audio/              # Audio (pipewire)
├── development/        # Dev tools, languages
├── virtualization/     # Docker, VMs
├── web-browsers/       # Browsers
├── window-manager/     # KDE Plasma
└── [category]/         # Other feature modules
```

### Adding New Modules

1. Create `.nix` file in appropriate `modules/` subdirectory
2. Follow namespace pattern or create named module
3. No headers - start directly with Nix code
4. Module automatically discovered - no manual imports needed

## Build Script Details

The `build.sh` script:
- Runs `git add .` automatically before building
- Formats code with `nix fmt`
- Validates with `nix flake check`
- Updates flake inputs (unless `--offline`)
- Configures experimental features automatically
- Sets `abort-on-warn=true` and `accept-flake-config=true`
- Disables sandbox for performance
- Shows "Build failed!" on errors

Options:
- `--host HOST` / `-t HOST` - Target host (system76/tec)
- `--offline` / `-o` - Skip flake updates
- `--collect-garbage` / `-d` - Run GC twice after build
- `--optimize` / `-O` - Optimize store after build
- `--verbose` / `-v` - Verbose output

## Critical Warnings

### ⚠️ NEVER run without explicit user request:

- `./build.sh` - Makes system-wide changes
- `nixos-rebuild switch` - Applies new configuration
- `git commit` - Commits changes
- `git push` - Pushes to remote

### ✅ SAFE to run anytime:

- `nix fmt` - Format check only
- `nix flake check` - Validation only
- `nixos-rebuild build` - Dry-run build
- `pre-commit run` - Linting checks
- `generation-manager score` - Compliance check

## Common Pitfalls

1. **Never use `pkgs` at file level** - Only inside returned function
2. **Never use literal imports** - Use namespace references
3. **Never create module headers** - Start with Nix code
4. **Never skip pipe operators** - Required experimental feature
5. **Always validate after changes** - Run pre-commit hooks
6. **Git shows many modified files after formatting** - Normal, review with `git diff`

## Troubleshooting

### Common Errors

**`attribute 'pkgs' missing`**
- Wrap module in function: `{ pkgs, ... }: { ... }`

**`infinite recursion`**
- Check for circular namespace references

**`pipe operator` error**
- Add `--extra-experimental-features "pipe-operators"`

### Debug Commands

```bash
# Check specific config values
nix eval .#nixosConfigurations.$(hostname).config.networking.hostName

# Verbose build trace
nix build --show-trace .#nixosConfigurations.$(hostname).config.system.build.toplevel

# Interactive exploration
nix repl /home/vx/nixos

# Check module loading
nix eval .#debug.allModules | jq | grep "module-name"
```

## Development Shell

The `nix develop` shell provides:
- `nixfmt-rfc-style` - Nix formatter
- `nil` - Nix LSP
- `nix-tree` - Dependency explorer
- `nix-diff` - Generation comparison
- `treefmt` - Multi-language formatter
- `generation-manager` - System management
- Pre-commit hooks auto-installed

## Allowed Claude Code Commands

These commands run without user approval (configured in `.claude/settings.local.json`):
- `WebSearch` - Web search capability
- `nix-instantiate:*` - Nix evaluation
- `nix fmt:*` - Code formatting
- `nix flake check:*` - Validation
- `nix log:*` - Build logs
- `nix develop:*` - Dev shell
- MCP tools for sequential thinking and documentation

## Quick Validation Checklist

Before any system changes:
```bash
# 1. Format check
nix fmt

# 2. Pre-commit validation
nix develop -c pre-commit run --all-files

# 3. Dendritic compliance
generation-manager score  # Should be 100/100

# 4. Flake validation
nix flake check --accept-flake-config

# 5. Dry-run build
nixos-rebuild build --flake .#$(hostname)
```

Only proceed with `./build.sh` if all checks pass and user explicitly requests system changes.