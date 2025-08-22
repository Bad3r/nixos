# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Reference

**Most common tasks:**

```bash
# Format and validate code (run after changes)
nix fmt && nix flake check

# Build system (ONLY when user requests)
./build.sh

# Enter development shell
nix develop

# View current generation
generation-manager current
```

## Repository Overview

This is a NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery. The configuration follows the golden standard implementation from `mightyiam/infra`.

### System Information

- **Hosts**:
  - `system76` - System76 laptop with NVIDIA GPU, LUKS encryption, and Btrfs filesystem
  - `tec` - GMKtec K7 Plus mini PC with Intel graphics, LUKS encryption, and ext4 filesystem (Asia/Riyadh timezone)
- **User**: `vx` (defined in `modules/meta/owner.nix`)
- **Desktop Environment**: KDE Plasma 6 with Wayland

### Core Dependencies

- **nixpkgs**: Unstable channel
- **flake-parts**: Module system foundation
- **import-tree**: Automatic module discovery
- **home-manager**: User environment management
- **stylix**: System-wide theming
- **nixvim**: Neovim configuration framework
- **treefmt-nix**: Multi-language formatting
- **nixos-hardware**: Hardware-specific configurations
- **ucodenix**: CPU microcode management
- **sink-rotate**: Audio sink rotation utility
- **git-hooks**: Pre-commit hooks via cachix
- **nix-index-database**: Command-not-found database
- **nixos-facter-modules**: System facts collection module
- **make-shell**: Shell environment management

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
# Build and switch to new configuration using convenience script
# Note: Automatically runs 'git add .' before building
./build.sh

# Build with optimization and garbage collection (recommended for storage management)
./build.sh --collect-garbage --optimize --offline

# Build for specific host (system76 or tec)
./build.sh --host tec
# Or: ./build.sh -t tec

# Build with specific flake directory
./build.sh --flake-dir /path/to/nixos
# Or: ./build.sh -p /path/to/nixos

# Build with verbose output
./build.sh --verbose
# Or: ./build.sh -v

# Build with all optimizations for offline work
./build.sh --collect-garbage --optimize --offline --host system76
# Or: ./build.sh -d -O -o -t system76

# Show help for all build options
./build.sh --help
# Or: ./build.sh -h

# Quick reference for build.sh flags:
# -p, --flake-dir PATH    Set configuration directory
# -t, --host HOST         Specify target hostname
# -o, --offline           Build in offline mode
# -v, --verbose           Enable verbose output
# -d, --collect-garbage   Run garbage collection after build
# -O, --optimize          Optimize Nix store after build
# -h, --help              Show help message

# Note: build.sh automatically:
# - Runs 'git add .' before building (stages all changes)
# - Formats code with 'nix fmt'
# - Validates flake with 'nix flake check'
# - Updates flake inputs (unless --offline)

# Build the system configuration (direct nix command)
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Format all Nix files
nix fmt

# Enter development shell with formatting and analysis tools
nix develop

# Emergency: Boot previous generation (at systemd-boot menu)
# Select older generation and press Enter

# Emergency: Rollback to previous generation
sudo nixos-rebuild switch --rollback
```

### Building and Testing

```bash
# Build the system configuration for system76
nix build .#nixosConfigurations.system76.config.system.build.toplevel --extra-experimental-features "nix-command flakes pipe-operators"

# Build for tec host
nix build .#nixosConfigurations.tec.config.system.build.toplevel --extra-experimental-features "nix-command flakes pipe-operators"

# Alternative build with nixos-rebuild
sudo nixos-rebuild build --flake .#system76 --extra-experimental-features "nix-command flakes pipe-operators"

# Switch to new configuration (apply changes)
sudo nixos-rebuild switch --flake .#system76 --extra-experimental-features "nix-command flakes pipe-operators"

# Check flake validity
nix flake check --accept-flake-config --extra-experimental-features "nix-command flakes pipe-operators"

# Show flake outputs
nix flake show --accept-flake-config --extra-experimental-features "nix-command flakes pipe-operators"

# Enter development shell
nix develop --accept-flake-config --extra-experimental-features "nix-command flakes pipe-operators"
```

### Code Quality

```bash
# Format Nix files (uses nixfmt-rfc-style via treefmt)
# Note: Formatting is automatically applied by build.sh before building
nix fmt

# Check flake validity (includes abort-on-warn enforcement)
nix flake check --accept-flake-config

# Show flake outputs
nix flake show

# Explore dependencies (requires nix-tree package)
nix-tree

# Validate dendritic pattern compliance
generation-manager score

# Query available packages
nix-env -qaP '*' --description | grep <package>

# Check store dependencies
nix-store -q --requisites <path> | grep <package>
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

# Clean old generations (keep only last 5)
generation-manager clean 5

# Remove all old generations system-wide
sudo nix-collect-garbage -d

# Optimize nix store (deduplicate files)
nix-store --optimise

# Channel management (if not using flakes)
nix-channel --list
nix-channel --add https://channels.nixos.org/nixos-unstable nixos
nix-channel --update
```

## Module Architecture

### Module Structure Pattern

```nix
# For modules needing packages (wrap in function):
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = { pkgs, ... }: {
    # Can use pkgs here
    environment.systemPackages = [ pkgs.vim ];
  };
}

# For simple modules (no function wrapper needed):
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = {
    # Direct configuration without pkgs
    services.openssh.enable = true;
    networking.hostName = "myhost";
  };
}
```

**Key point**: `pkgs` is NOT available at the file level due to flake-parts context. Only use `pkgs` inside the returned function.

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
- `modules/meta/generation-manager.nix` - System generation management tool
- `modules/home-manager-setup.nix` - Home Manager integration
- `modules/configurations/nixos.nix` - System configuration framework
- `modules/{base,pc,workstation}.nix` - Namespace composition chains
- `modules/flake-parts-modules.nix` - Flake-parts configuration with import-tree
- `modules/treefmt-wrapper.nix` - Code formatting configuration
- `modules/base/hardware-scan.nix` - Hardware detection and firmware support
- `modules/base/system-activation.nix` - System activation scripts
- `modules/base/nix-settings.nix` - Core Nix configuration (512MB download buffer)

### Host Configuration

**Primary Host: `system76`**

- `modules/system76/imports.nix` - Main host configuration entry point
- Host-specific modules include:
  - `boot.nix` - Boot configuration with LUKS encryption
  - `hardware-config.nix` - Hardware-specific settings
  - `nvidia-gpu.nix` - NVIDIA GPU support
  - `network.nix` - Network configuration
  - `services.nix` - System services
  - `fonts.nix` - Font configuration
  - `hostname.nix`, `host-id.nix`, `domain.nix` - System identification
  - `ssh.nix` - SSH server configuration
  - `users.nix` - User account settings
  - `teamviewer.nix` - Remote support software
- Uses `configurations.nixos.system76.module` pattern
- Namespace: `workstation` (includes base → pc → workstation)

**Secondary Host: `tec`**

- `modules/tec/imports.nix` - Main host configuration entry point
- Host-specific modules follow same pattern as system76
- Uses `configurations.nixos.tec.module` pattern
- Namespace: `workstation` (includes base → pc → workstation)

### Module Categories

- `modules/archive-mngmt/` - Archive management tools (file-roller, CLI tools)
- `modules/audio/` - Audio system configuration (pipewire)
- `modules/boot/` - Boot configuration (storage, compression, visuals)
- `modules/clipboard-mgmnt/` - Clipboard management (copyq)
- `modules/development/` - Development tools and environments (includes nix-ld)
- `modules/home/` - Home Manager modules (includes backup-collisions.nix)
- `modules/networking/` - Network and SSH configuration
- `modules/security/` - Security tools and secrets management
- `modules/storage/` - Storage management (swap, redundancy)
- `modules/terminal/terminal-emulators/` - Terminal emulators (alacritty, cosmic-term, kitty, wezterm)
- `modules/virtualization/` - Container and VM support
- `modules/window-manager/` - Desktop environment (KDE/Plasma)
- `modules/gaming/` - Gaming-related configurations
- `modules/media.nix` - Media applications and codecs
- `modules/bluetooth.nix` - Bluetooth support configuration

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
4. After any major change or task completion, run:
   ```bash
   nix fmt              # Format all Nix files
   nix flake check      # Validate configuration
   ```

**⚠️ CRITICAL**: Do NOT run `./build.sh` or `nixos-rebuild` unless the user explicitly requests it. Building and switching configurations can have immediate system-wide effects.

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

The `build.sh` script automatically configures these experimental features along with:

- `abort-on-warn = true` (enforces warning-free code)
- `accept-flake-config = true` (accepts flake configuration)
- `allow-import-from-derivation = true` (enabled in script environment)
- Runs `git add .` automatically before building (stages all changes)
- Disables Nix sandbox for performance (`sandbox = false`)
- Runs `nix fmt` before building to ensure consistent formatting
- Validates flake configuration with `nix flake check` before building
- Updates all flake inputs unless `--offline` is specified
- Performs double garbage collection when using `--collect-garbage` flag for thorough cleanup
- Configures optimal build settings: `cores = 0`, `max-jobs = auto`
- Uses `nixos-rebuild switch` internally with the specified flake and host
- Sets up error trapping to display "Build failed!" on any error

### Metadata Usage

Only owner metadata should be centralized in `modules/meta/owner.nix`. System-specific settings go directly in modules.

### Module Discovery

All `.nix` files in `modules/` are automatically imported except those starting with `_`.

### Library Prefixes

Custom library functions use consistent prefixes (e.g., `mightyiam.lib.*`).

## Common Pitfalls to Avoid

1. **Never create module headers** - No comments at the top of `.nix` files
2. **Never use literal imports** - No `imports = [ ./file.nix ]`, use namespaces instead
3. **Never access `pkgs` at file level** - Only inside the returned function
4. **Never skip pipe operators** - Always enable experimental feature
5. **Never use feature flags** - Anti-pattern in dendritic architecture
6. **Never mix namespace and named modules** - Use named modules only for optional features

## Troubleshooting

### Common Errors & Solutions

**`attribute 'pkgs' missing`**

- Wrap module in function: `flake.modules.nixos.namespace = { pkgs, ... }: { ... }`

**`expected a set but got a function`**

- Remove function wrapper if module doesn't need `pkgs`

**`infinite recursion`**

- Check for circular namespace references

**`pipe operator` error**

- Add `--extra-experimental-features "pipe-operators"`

**`pkgs is undefined`**

- Only use `pkgs` inside the returned function, not at file level

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

### System Recovery

For kernel panic or boot issues, see `docs/RECOVERY_GUIDE.md`. Quick emergency boot:

1. **At systemd-boot**: Press `Space`, select entry, press `e`
2. **Add kernel params**: `modprobe.blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0`
3. **Press Enter** to boot

For LUKS-encrypted systems:

- Root: `/dev/disk/by-uuid/de5ef033-553b-4943-be41-09125eb815b2`
- Swap: `/dev/disk/by-uuid/555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec`

## Architecture Deep Dive

### Module Import Chain

The system uses a hierarchical namespace chain where each level extends the previous:

1. `base` modules define core system settings
2. `pc` imports `base` and adds desktop features
3. `workstation` imports `pc` and adds development tools
4. Host configuration (`system76` or `tec`) selects which namespace to use

### Flake-parts Integration

- All `.nix` files in `modules/` are auto-imported via `import-tree` through flake-parts
- The entry point is: `outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } { imports = [ (inputs.import-tree ./modules) ]; }`
- Modules contribute to `flake.modules.nixos.*` namespaces
- Host configurations are built via `configurations.nixos.<hostname>.module` pattern
- The flake-parts context is established in `modules/flake-parts-modules.nix`
- System architecture is hardcoded to `x86_64-linux` in `modules/configurations/nixos.nix`

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
- `generation-manager` - System generation management utility

## Generation Management

The `generation-manager` tool provides comprehensive system management:

- `generation-manager list` - List all system generations
- `generation-manager current` - Show current generation info
- `generation-manager clean [N]` - Keep only N most recent generations (default: 5)
- `generation-manager switch <host>` - Switch to configuration for host
- `generation-manager rollback [N]` - Rollback N generations (default: 1)
- `generation-manager diff <g1> <g2>` - Compare two generations
- `generation-manager gc` - Run garbage collection
- `generation-manager score` - Calculate Dendritic Pattern compliance (checks 7 metrics)
- `generation-manager info <gen>` - Show detailed generation info

Set `DRY_RUN=true` to preview commands without executing them.

### Dendritic Pattern Compliance Scoring

The `generation-manager score` command evaluates:

1. No literal path imports (20 points)
2. input-branches module exists (10 points)
3. generation-manager tool exists (10 points)
4. Module headers complete (20 points)
5. No TODOs remaining (10 points)
6. nvidia-gpu has specialisation (15 points)
7. Metadata properly configured (15 points)

Total: 100 points for full compliance

## Additional Documentation

The `docs/` directory contains detailed guides:

- `DENDRITIC_PATTERN_PRINCIPLES.md` - Core principles of the Dendritic Pattern
- `DENDRITIC_PATTERN_REFERENCE.md` - Complete reference implementation
- `DENDRITIC_PATTERN_BEST_PRACTICES.md` - Best practices for Dendritic Pattern
- `DENDRITIC_PATTERN_IMPLEMENTATION.md` - Implementation details
- `DENDRITIC_PATTERN_MIGRATION.md` - Migration guide to Dendritic Pattern
- `BOOT_CONFIGURATION_REFERENCE.md` - Boot configuration details
- `RECOVERY_GUIDE.md` - System recovery procedures
- `MODULE_STRUCTURE_GUIDE.md` - Module organization guidelines
- `logseq-fhs-build-guide.md` - Guide for building Logseq with FHS

## Claude Code Configuration

The `.claude/settings.local.json` file configures special permissions:

- **Allowed commands without user approval**:
  - `WebSearch` - Web search capability for current information
  - `nix-instantiate:*` - Nix expression evaluation commands
  - `plasma-apply-lookandfeel:*` - KDE Plasma theme application commands

## Local Documentation

NixOS includes extensive local documentation:

- **Manual pages**: `man configuration.nix`, `man home-configuration.nix`
- **NixOS manual**: Use `nixos-help` command to open the full manual in a browser
- **Build logs**: `nix log <package-path>` to show build logs if available
- **Local docs**: Complete NixOS documentation available in `nixos_docs_md/` directory
  - Numbered files (001-460) covering all NixOS topics
  - Topics include: installation, configuration syntax, package management, services, hardware support, and advanced features
  - Use `ls nixos_docs_md/` to browse available documentation
