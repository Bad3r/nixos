# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery. The configuration follows the golden standard implementation from `mightyiam/infra`.

### Core Dependencies

- **nixpkgs**: Unstable channel
- **flake-parts**: Module system foundation
- **import-tree**: Automatic module discovery
- **home-manager**: User environment management
- **stylix**: System-wide theming
- **nixvim**: Neovim configuration framework
- **treefmt-nix**: Multi-language formatting

### Key Architecture Concepts

1. **Dendritic Pattern**: Modules grow organically without explicit imports
2. **Import-tree**: All `.nix` files in `modules/` are automatically imported via flake-parts
3. **Namespace Composition**: Modules contribute to shared namespaces (`base` → `pc` → `workstation`)
4. **Pipe Operators**: Mandatory experimental Nix feature used throughout
5. **No Headers**: Modules start directly with Nix code - no comments or documentation headers
6. **Function-based Modules**: Modules needing `pkgs` must return a function

## Essential Commands

### Quick Start (Most Common Commands)

```bash
# Build the system configuration (most common)
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Format all Nix files
nix fmt

# Enter development shell with formatting and analysis tools
nix develop
```

### Building and Testing

```bash
# Build the system configuration
nix build .#nixosConfigurations.system76.config.system.build.toplevel --extra-experimental-features "nix-command flakes pipe-operators"

# Alternative build with nixos-rebuild
sudo nixos-rebuild build --flake .#system76 --extra-experimental-features "nix-command flakes pipe-operators"

# Switch to new configuration (apply changes)
sudo nixos-rebuild switch --flake .#system76 --extra-experimental-features "nix-command flakes pipe-operators"

# Check flake validity
nix flake check --extra-experimental-features "nix-command flakes pipe-operators"

# Show flake outputs
nix flake show --extra-experimental-features "nix-command flakes pipe-operators"

# Enter development shell
nix develop --extra-experimental-features "nix-command flakes pipe-operators"
```

### Code Quality

```bash
# Format Nix files (uses treefmt with nixfmt-rfc-style, prettier, shfmt)
nix fmt

# Alternative formatting command
treefmt .

# Explore dependencies (requires nix-tree package)
nix-tree

# Validate dendritic pattern compliance
generation-manager score
```

### System Management

```bash
# View current generation
generation-manager current

# List all generations
generation-manager list

# Switch to a generation
sudo generation-manager switch <number>

# Update specific flake inputs
nix flake update nixpkgs home-manager
```

## Module Architecture

### Module Structure Pattern

```nix
# For modules needing packages:
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = { pkgs, ... }: {
    # Configuration using pkgs
  };
}

# For simple modules:
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = {
    # Direct configuration
  };
}
```

### Namespace Hierarchy

- `base` - Core system configuration (all systems)
- `pc` - Desktop/workstation features (extends base)
- `workstation` - Development environment (extends pc)

### Critical Rules

1. **No explicit imports** - Modules reference each other through namespaces only
2. **No module headers** - Start directly with Nix code (no comments at top)
3. **Use pipe operators** - Required experimental feature (must be enabled in all nix commands)
4. **Named modules only for optional features** - Like `nvidia-gpu`, `swap`, `security-tools`
5. **Metadata only for owner info** - No feature flags or package versions
6. **abort-on-warn = true** - Required in nixConfig for dendritic compliance
7. **Flake-parts context** - `pkgs` is NOT available at module file level
8. **Host pattern** - Hosts must use `configurations.nixos.<hostname>.module` pattern
9. **No literal path imports** - Never use `imports = [ ./some/file.nix ]`

## File Organization

### Core Modules

- `modules/meta/owner.nix` - Owner metadata (username, email, SSH keys)
- `modules/home-manager-setup.nix` - Home Manager integration
- `modules/configurations/nixos.nix` - System configuration framework
- `modules/{base,pc,workstation}.nix` - Namespace composition chains
- `modules/flake-parts-modules.nix` - Flake-parts configuration with import-tree

### Host Configuration

**Primary Host: `system76`**
- `modules/system76/imports.nix` - Main host configuration entry point
- Host-specific modules include:
  - `boot.nix` - Boot configuration with LUKS encryption
  - `filesystem.nix` - Btrfs with compression
  - `hardware-config.nix` - Hardware-specific settings
  - `nvidia-gpu.nix` - NVIDIA GPU support
  - `network.nix` - Network configuration
  - `services.nix` - System services
  - `swap.nix` - Swap configuration (32GB)
- Uses `configurations.nixos.system76.module` pattern
- Namespace: `workstation` (includes base → pc → workstation)

### Module Categories

- `modules/audio/` - Audio system configuration (pipewire)
- `modules/boot/` - Boot configuration (storage, initrd, visuals)
- `modules/development/` - Development tools and environments
- `modules/home/` - Home Manager modules
- `modules/networking/` - Network and SSH configuration
- `modules/security/` - Security tools and secrets management
- `modules/storage/` - Storage management (swap, redundancy)
- `modules/virtualization/` - Container and VM support
- `modules/window-manager/` - Desktop environment (KDE/Plasma)

### Testing Philosophy

The configuration relies on:
- Build-time validation via Nix's type system
- Dendritic pattern's inherent structural safety
- TOML generation for change tracking (`modules/meta/all-check-store-paths.nix`)
- Generation manager's compliance scoring

## Common Development Tasks

### Adding a New Module

1. Create file in appropriate directory under `modules/`
2. Follow namespace pattern (contribute to existing namespace or create named module)
3. No headers or comments at top of file
4. Module automatically discovered by import-tree

### Modifying System Configuration

1. Check namespace hierarchy: base → pc → workstation
2. Add configuration to appropriate namespace level
3. Use `config.flake.modules.nixos.*` to reference other modules
4. Test with: `nix build .#nixosConfigurations.system76.config.system.build.toplevel`

### Managing Unfree Packages

Add to appropriate module:

```nix
nixpkgs.allowedUnfreePackages = [ "package-name" ];
```

## Important Notes

### Experimental Features Required

Always include `--extra-experimental-features "nix-command flakes pipe-operators"` or set:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
```

### Metadata Usage

Only owner metadata should be centralized in `modules/meta/owner.nix`. System-specific settings go directly in modules.

### Module Discovery

All `.nix` files in `modules/` are automatically imported except those starting with `_`.

### Library Prefixes

Custom library functions use consistent prefixes (e.g., `mightyiam.lib.*`).

## Troubleshooting

### Common Errors & Solutions

| Error | Solution |
|-------|----------|
| `attribute 'pkgs' missing` | Wrap module in function: `flake.modules.nixos.namespace = { pkgs, ... }: { ... }` |
| `expected a set but got a function` | Remove function wrapper if module doesn't need `pkgs` |
| `infinite recursion` | Check for circular namespace references |
| `pipe operator` error | Add `--extra-experimental-features "pipe-operators"` |
| `pkgs is undefined` | Only use `pkgs` inside the returned function, not at file level |

### Debug Commands

```bash
# Interactive module exploration
nix repl /home/vx/nixos
> :p flake.modules.nixos

# Check specific values
nix eval .#nixosConfigurations.system76.config.networking.hostName

# Verbose build trace
nix build --show-trace .#nixosConfigurations.system76.config.system.build.toplevel
```

## Architecture Deep Dive

### Module Import Chain

The system uses a hierarchical namespace chain where each level extends the previous:

1. `base` modules define core system settings
2. `pc` imports `base` and adds desktop features
3. `workstation` imports `pc` and adds development tools
4. Host configuration (`system76`) selects which namespace to use

### Flake-parts Integration

- All `.nix` files in `modules/` are auto-imported via `import-tree`
- The entry point is: `outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);`
- Modules contribute to `flake.modules.nixos.*` namespaces
- Host configurations are built via `configurations.nixos.<hostname>.module`

### Package Access Pattern

Modules needing packages must wrap their configuration in a function:

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = { pkgs, ... }: {
    # Can use pkgs here
  };
}
```

## Recent Migration Context

The configuration was recently migrated to the Dendritic Pattern (2025-08-12), achieving 100/100 compliance. Key changes included:

- Removed all module headers
- Eliminated feature flags (anti-pattern)
- Reorganized to namespace-based composition
- Fixed library prefix inconsistencies
- Simplified testing to TOML generation only

## Development Shell

The development shell (via `nix develop`) provides:
- `nixfmt-rfc-style` - Nix code formatter
- `nil` - Nix LSP for IDE integration
- `nix-tree` - Dependency exploration
- `nix-diff` - Generation comparison
- `jq`/`yq` - JSON/YAML processing
- `treefmt` - Multi-language formatter

## Generation Management

The `generation-manager` tool provides comprehensive system management:
- `generation-manager list` - List all system generations
- `generation-manager current` - Show current generation info
- `generation-manager clean [N]` - Keep only N most recent generations
- `generation-manager switch <host>` - Switch to configuration for host
- `generation-manager rollback [N]` - Rollback N generations
- `generation-manager diff <g1> <g2>` - Compare two generations
- `generation-manager gc` - Run garbage collection
- `generation-manager score` - Calculate Dendritic Pattern compliance
- `generation-manager info <gen>` - Show detailed generation info

Set `DRY_RUN=true` to preview commands without executing them.
