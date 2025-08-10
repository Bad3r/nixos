# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal NixOS/Home Manager configuration using the **Dendritic Pattern** - an architecture where modules grow organically like dendrites, with automatic discovery and namespace-based composition. Uses Nix Flakes, flake-parts, and import-tree.

### Architecture Principles
- **Automatic Module Discovery**: All `.nix` files in `modules/` are auto-imported via import-tree
- **No Explicit Imports**: Modules reference each other through namespaces, never file paths
- **Metadata-Driven**: All configurable values live in `flake.meta`
- **Namespace Composition**: Multiple modules contribute to shared namespaces that merge automatically

### Current State
- **Framework**: ✅ Dendritic pattern fully implemented with automatic imports
- **Host**: ✅ System76 laptop with NVIDIA/Intel hybrid graphics, LUKS encryption
- **Desktop**: ✅ KDE Plasma 6 with comprehensive configuration
- **Development**: ✅ Multi-language toolchains, Docker, databases
- **Shell**: ✅ DevShell with treefmt, statix, deadnix
- **Testing**: ✅ Dendritic compliance tests, module tests, integration tests

## Critical Requirements

### Pipe Operators (MANDATORY)
**IMPORTANT:** This configuration uses pipe operators (`|>`) extensively. ALL nix commands must include:
```bash
--extra-experimental-features pipe-operators
```
Or set environment variable:
```bash
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
```

## Essential Commands

### Primary Build & Deploy
```bash
# Full build with optimizations (recommended)
./build.sh --collect-garbage --optimize --offline

# Quick rebuild
nixos-rebuild switch --flake .#system76 --use-remote-sudo

# Test build without switching
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Test in VM before deployment
nixos-rebuild build-vm --flake .#system76
```

### Development
```bash
# Enter development shell
nix develop

# Format all code (Nix, JSON, shell scripts)
nix fmt
# or
treefmt

# Validate flake
nix flake check

# Show all outputs
nix flake show

# Update dependencies
nix flake update

# Static analysis
statix check

# Find dead code
deadnix

# Explore dependencies
nix-tree
```

### Testing & Validation
```bash
# Test dendritic pattern compliance
./test-dendritic-compliance.sh

# Test named modules
./test-named-modules.sh

# Quick validation build
./test-build.sh

# Verify boot configuration
./verify-boot-config.sh

# Final boot check
./final-boot-check.sh

# Generate module dependency graph
./generate-dependency-graph.sh
```

### Debugging
```bash
# Interactive REPL exploration
nix repl .
> :l
> flake.modules.nixos.<TAB>
> flake.modules.homeManager.<TAB>

# Check specific values
nix eval .#nixosConfigurations.system76.config.networking.hostName
nix eval .#nixosConfigurations.system76.config.system.stateVersion

# Show module exports
nix eval .#flake.modules.nixos --json | jq .

# List installed packages
nix eval .#nixosConfigurations.system76.config.environment.systemPackages --apply 'builtins.map (p: p.name)'
```

## Architecture & Module System

### Namespace Hierarchy
```
flake.modules.nixos.base       # Core system (ALL systems need)
flake.modules.nixos.pc          # Personal computer features
flake.modules.nixos.workstation # Development features (imports pc→base)
flake.modules.nixos."name"      # Named modules (optional features)
flake.modules.homeManager.base  # User environment (CLI/minimal)
flake.modules.homeManager.gui   # Graphical user environment
```

### Module Discovery & Composition
```
modules/
├── meta/           # Metadata & configuration
│   └── owner.nix   # Central metadata (username, email, etc.)
├── base/           # Core system modules
├── pc/             # Desktop/laptop modules
├── workstation/    # Development modules
├── system76/       # Host-specific configuration
├── home/           # Home-manager modules
│   ├── base/       # CLI environment
│   └── gui/        # GUI applications
└── *.nix           # All auto-imported
```

### Named Modules (Golden Standard)
Only create named modules for features needed by SOME but not ALL systems:
- `efi` - UEFI boot (not all systems use UEFI)
- `swap` - Swap configuration (not all systems need swap)
- `nvidia-gpu` - NVIDIA graphics (hardware-specific)

### Module Patterns

#### Basic Module
```nix
{ config, lib, pkgs, ... }:
{
  flake.modules.nixos.pc = {
    # Configuration
  };
}
```

#### Using Metadata
```nix
{ config, ... }:
{
  flake.modules.nixos.base = {
    users.users.${config.flake.meta.owner.username} = {
      description = config.flake.meta.owner.name;
    };
  };
}
```

#### Conditional Features
```nix
{ config, lib, ... }:
{
  flake.modules.nixos.workstation = lib.mkIf config.flake.meta.features.development {
    # Development tools
  };
}
```

## Key Metadata (modules/meta/owner.nix)

Central configuration values used throughout:
- **Owner**: username=`vx`, email=`bad3r@unsigned.sh`
- **System**: timezone=`Asia/Riyadh`, stateVersion=`25.05`
- **Network**: SSH port=`6234`
- **Features**: development=`true`, virtualization=`true`

## System76 Hardware Specifics

- **Boot**: systemd-boot with LUKS encryption (2 devices)
  - Root: UUID=de5ef033-553b-4943-be41-09125eb815b2
  - Swap: UUID=555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec
- **Graphics**: NVIDIA/Intel hybrid with PRIME sync
  - Intel: PCI:0:2:0
  - NVIDIA: PCI:1:0:0
- **Filesystem**: ext4 root, FAT32 /boot (umask 0077)

## Development Environment

### Languages & Tools
- **Node.js**: v22
- **Python**: 3.12 with common packages
- **Rust**: rustc, cargo, clippy, rustfmt
- **Go**: Latest stable
- **Clojure**: Leiningen, Boot
- **Databases**: PostgreSQL 16, Redis
- **Containers**: Docker with NVIDIA support

### Shell Environment
- **Default**: Zsh with oh-my-zsh
- **Prompt**: Starship
- **Tools**: fzf, ripgrep, eza, bat, yazi
- **Terminal**: Kitty with Tokyo Night theme
- **Editor**: Neovim with LSP, Treesitter

## Working with Modules

### Adding a New Module
1. Create file in appropriate directory under `modules/`
2. Export to correct namespace (base/pc/workstation or named)
3. Use metadata from `config.flake.meta` instead of hardcoding
4. Module is automatically discovered - no import needed

### Debugging Module Issues
- **Infinite recursion**: Check for circular dependencies
- **Option conflicts**: Use `lib.mkForce` or `lib.mkDefault`
- **Module not found**: Ensure `.nix` extension and correct location
- **Metadata missing**: Check `modules/meta/owner.nix`

## Common Tasks

### Update System
```bash
# Update flake inputs and rebuild
nix flake update
./build.sh

# Update specific input
nix flake lock --update-input nixpkgs
```

### Test Changes
```bash
# Build without switching
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Test in VM
nixos-rebuild build-vm --flake .#system76
```

### Rollback
```bash
# List generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Switch to previous
sudo nixos-rebuild switch --rollback
```

## Important Notes

- **User**: System configured for user `vx` (defined in meta/owner.nix)
- **Dendritic Pattern**: Never use explicit imports, rely on automatic discovery
- **Metadata First**: All configurable values should reference `flake.meta`
- **Experimental Features**: Uses pipe operators (enabled in nixConfig)
- **State Version**: Currently "25.05" - do not change without migration

## Reference Documentation

- Dendritic Pattern Guide: `DENDRITIC_PATTERN_GUIDE.md`
- Migration Status: `MIGRATION_STATUS.md`
- Module Structure: `docs/MODULE_STRUCTURE_GUIDE.md`