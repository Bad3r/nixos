# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Reference

**Most common tasks:**

```bash
# Validate changes (run after ANY modification to .nix files)
nix develop -c pre-commit run --all-files

# Enter development shell (includes pre-commit hooks setup)
nix develop

# Build and switch configuration (⚠️ system-wide changes!)
./build.sh

# Build with optimizations (recommended)
./build.sh --collect-garbage --optimize --offline

# View current generation
generation-manager current

# Check git status (many files may show as modified due to formatting)
git status
```

**Validation workflow after changes:**

1. Run pre-commit hooks: `nix develop -c pre-commit run --all-files`
2. If issues found → Create a plan to fix them
3. Implement fixes systematically
4. Re-run hooks until all pass
5. Final check: `nix flake check --accept-flake-config`

## Repository Overview

This is a NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery. The configuration follows the golden standard implementation from `mightyiam/infra`.

### Available Documentation

⚠️ **IMPORTANT**: Always use local NixOS documentation first - do NOT use WebSearch, WebFetch, or Context7

- **Local NixOS docs** (PRIMARY SOURCE): Complete offline documentation in `nixos_docs_md/` directory (460+ files)
  - **ALWAYS search here first** for NixOS-related questions
  - Browse with: `ls nixos_docs_md/` or search with: `grep -r "topic" nixos_docs_md/`
  - Topics include: installation, configuration syntax, package management, services, hardware
  - Example: `grep -r "postgresql" nixos_docs_md/` to find PostgreSQL configuration docs
  - All NixOS module options and configurations are documented locally
- **Dendritic Pattern docs**: Detailed guides in `docs/` directory
- **Man pages**: `man configuration.nix`, `man home-configuration.nix`
- **NixOS manual**: `nixos-help` command opens full manual in browser
- **Logseq build guide**: `docs/logseq-fhs-build-guide.md` - Building Logseq from source in FHS environment

### System Information

- **Hosts**:
  - `system76` - System76 laptop with NVIDIA GPU, LUKS encryption, and Btrfs filesystem
  - `tec` - GMKtec K7 Plus mini PC with Intel graphics, LUKS encryption, and ext4 filesystem (Most current host)
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

⚠️ **IMPORTANT**: Only run `./build.sh` when the user explicitly requests to build/switch the system configuration. This command makes system-wide changes.

```bash
# Build and switch to new configuration using convenience script
# WARNING: This applies changes system-wide - only run when explicitly requested!
# Note: Automatically runs 'git add .' before building
./build.sh

# Build with optimization and garbage collection (recommended for storage management)
./build.sh --collect-garbage --optimize --offline

# Build for specific host (system76 or tec)
./build.sh --host tec
# Or: ./build.sh -t tec

# Build with verbose output
./build.sh --verbose
# Or: ./build.sh -v

# Build with all optimizations for offline work
./build.sh --collect-garbage --optimize --offline --host system76
# Or: ./build.sh -d -O -o -t system76

# Show help for all build options
./build.sh --help

# build.sh automation features:
# - Runs 'git add .' before building (stages all changes)
# - Formats code with 'nix fmt'
# - Validates flake with 'nix flake check'
# - Updates flake inputs (unless --offline)
# - Configures experimental features (nix-command, flakes, pipe-operators)
# - Sets abort-on-warn=true and accept-flake-config=true
# - Runs garbage collection twice when using --collect-garbage flag
# - Disables Nix sandbox for performance
# - Shows "Build failed!" on any error with proper error trapping

# Format all Nix files
nix fmt

# Enter development shell with formatting and analysis tools
nix develop

# Emergency: Rollback to previous generation
sudo nixos-rebuild switch --rollback
```

### Code Quality

```bash
# PRIMARY: Run all pre-commit hooks (formatting, dead code, anti-patterns)
nix develop -c pre-commit run --all-files

# Individual formatting commands (use pre-commit hooks instead when possible):
nix fmt                   # Format Nix files only
nix develop -c treefmt    # Format all file types

# Validation and checking:
nix flake check --accept-flake-config  # Validate flake (includes abort-on-warn)
nix flake show                          # Show flake outputs
generation-manager score                # Validate dendritic pattern compliance

# Dependency management:
nix flake update                        # Update all flake inputs
nix flake update nixpkgs home-manager   # Update specific inputs
nix-tree                                # Explore dependencies

# Package queries:
nix-env -qaP '*' --description | grep <package>  # Query available packages
nix-store -q --requisites <path> | grep <package>  # Check store dependencies
```

### Pre-commit Hooks & Linting

**Pre-commit hooks** (automatically run on git commit):

- `nixfmt-rfc-style` - Nix code formatting
- `deadnix` - Find and remove dead Nix code
- `statix` - Nix anti-pattern linter

**Workflow for addressing linting issues:**

```bash
# Step 1: Run all hooks to identify issues
nix develop -c pre-commit run --all-files

# Step 2: If issues found, STOP and create a plan:
# - List all issues by type
# - Identify root causes
# - Plan fixes in order (formatting → dead code → anti-patterns)
# - Use TodoWrite tool to track the plan

# Step 3: Implement fixes systematically
# Run specific hooks to verify each fix:
nix develop -c pre-commit run nixfmt-rfc-style --all-files  # Format issues
nix develop -c pre-commit run deadnix --all-files           # Dead code
nix develop -c pre-commit run statix --all-files            # Anti-patterns

# Step 4: Final verification
nix develop -c pre-commit run --all-files  # Must pass cleanly

# Additional commands:
pre-commit install        # Install hooks (done automatically in dev shell)
pre-commit run           # Run on staged files only
```

**IMPORTANT**:

- NEVER bypass pre-commit hooks! All issues must be addressed
- Create a plan BEFORE fixing issues to avoid cascading problems
- Many files may show as modified after formatting - this is normal

### System Management

```bash
# View current generation
generation-manager current

# List all generations
generation-manager list

# Switch to a generation
sudo generation-manager switch <number>

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

## CI/CD

- **GitHub Actions**: `.github/workflows/check.yml` - Automated compliance checking
  - Validates Dendritic Pattern compliance
  - Checks code formatting
  - Validates namespace usage
  - Builds configurations (dry-run)
  - Generates dependency graphs

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

**Secondary Host: `tec` (current)**

- `modules/tec/imports.nix` - Main host configuration entry point
- Host-specific modules follow same pattern as system76
- Uses `configurations.nixos.tec.module` pattern
- Namespace: `workstation` (includes base → pc → workstation)

### Module Categories

- `modules/archive-mngmt/` - Archive management tools (file-roller, CLI tools, zstd)
- `modules/audio/` - Audio system configuration (pipewire)
- `modules/boot/` - Boot configuration (storage, compression, visuals)
- `modules/clipboard-mgmnt/` - Clipboard management (copyq)
- `modules/containers/` - Container tools (docker-compose, dive, lazydocker)
- `modules/database/` - Database tools (sqlite)
- `modules/development/` - Development tools and environments (includes nix-ld, AI tools like Cursor)
- `modules/disk-management/` - Disk utilities (NTFS support)
- `modules/encryption/` - Encryption tools (veracrypt)
- `modules/file-management/` - File utilities (fzf, search, tree, view)
- `modules/file-managers/` - GUI file managers (pcmanfm)
- `modules/file-sharing/` - File sharing tools (localsend, qbittorrent)
- `modules/gaming/` - Gaming-related configurations (steam-run)
- `modules/git/` - Git tools (gh CLI, lazygit)
- `modules/graphics/` - Graphics applications (gimp, inkscape, krita)
- `modules/hardware/` - Hardware configuration (EFI)
- `modules/home/` - Home Manager modules (includes backup-collisions.nix)
- `modules/image-viewers/` - Image viewing tools (feh)
- `modules/languages/` - Programming languages (go, java, javascript with nrm, python, rust)
- `modules/media-players/` - Media players (mpv, vlc)
- `modules/messaging-apps/` - Communication tools (discord, slack, telegram, zoom, etc.)
- `modules/networking/` - Network and SSH configuration
- `modules/office/` - Office applications (libreoffice, obsidian, marktext)
- `modules/password-managers/` - Password management (bitwarden, keepassxc)
- `modules/pdf-viewers/` - PDF viewers (evince)
- `modules/screenshots/` - Screenshot tools (flameshot)
- `modules/security/` - Security tools and secrets management (gnupg, polkit)
- `modules/storage/` - Storage management (swap, redundancy, tmp)
- `modules/style/` - System theming (stylix)
- `modules/system-utilities/` - System utilities (desktop-file-utils)
- `modules/terminal/terminal-emulators/` - Terminal emulators (alacritty, cosmic-term, kitty, wezterm)
- `modules/virtualization/` - Container and VM support (docker, virtualbox)
- `modules/web-browsers/` - Web browsers (brave, firefox, tor-browser)
- `modules/window-manager/` - Desktop environment (KDE/Plasma)
- `modules/media.nix` - Media applications and codecs
- `modules/bluetooth.nix` - Bluetooth support configuration

### Testing Philosophy

The configuration relies on:

- Build-time validation via Nix's type system
- Dendritic pattern's inherent structural safety
- TOML generation for change tracking (`modules/meta/all-check-store-paths.nix`)
- Generation manager's compliance scoring

**Note**: There are no traditional unit tests. All validation happens at build time through:

- `nix flake check` - Type checking and validation
- `nix fmt` - Code formatting validation
- Build process itself - Configuration validity

### Testing & Validation Commands

```bash
# Dry-run build (validate without switching)
nixos-rebuild build --flake .#hostname

# Check flake outputs and structure
nix flake show

# Validate all flake outputs
nix flake check --accept-flake-config

# Check for dead code
nix develop -c deadnix .

# Check for anti-patterns
nix develop -c statix check .

# Test specific configuration attributes
nix eval .#nixosConfigurations.system76.config.networking.hostName

# Verbose error traces for debugging
nix build --show-trace .#nixosConfigurations.system76.config.system.build.toplevel

# Check dendritic pattern compliance score (should be 100/100)
generation-manager score
```

## Documentation Usage Guidelines

### When to Use Local Documentation

**Always use local docs for:**

- NixOS configuration options → `nixos_docs_md/`
- NixOS services setup → `nixos_docs_md/`
- Package management → `nixos_docs_md/`
- System administration → `nixos_docs_md/`
- Hardware configuration → `nixos_docs_md/`

**Search examples:**

```bash
# Find PostgreSQL configuration
grep -r "postgresql" nixos_docs_md/

# Find networking options
grep -r "networking\." nixos_docs_md/

# Find specific service documentation
ls nixos_docs_md/ | grep -i service_name
```

### When External Tools May Be Used

**Use WebSearch/Context7 only for:**

- Non-NixOS programming questions (Python, JavaScript, etc.)
- Third-party library documentation not in NixOS
- Current events or recent updates post-2025
- General programming patterns

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
4. **After any changes, follow this workflow:**

   ```bash
   # Step 1: Run pre-commit hooks to identify all issues
   nix develop -c pre-commit run --all-files

   # Step 2: If issues are found, create a plan to address them
   # - Review each issue type (formatting, dead code, anti-patterns)
   # - Determine root causes
   # - Plan fixes in logical order

   # Step 3: Implement fixes systematically
   # - Address one issue type at a time
   # - Run hooks after each fix to verify

   # Step 4: Final validation
   nix develop -c pre-commit run --all-files  # Should pass cleanly
   nix flake check --accept-flake-config      # Final validation
   ```

### Critical Workflow Rules

**⚠️ NEVER run these unless explicitly requested:**

- `./build.sh` or `nixos-rebuild switch` - These make system-wide changes
- `git commit` - Never commit unless user explicitly asks
- `git push` - Never push to remote unless user explicitly asks

**✅ SAFE to run without asking:**

- `nix fmt` - Code formatting (read-only check)
- `nix flake check` - Validation (read-only)
- `nix build` or `nixos-rebuild build` - Dry-run builds for validation
- `pre-commit run` - Linting and formatting checks
- `generation-manager score` - Compliance checking

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

## Git Status and Modified Files

**Note**: After running `nix fmt`, many files may show as modified in `git status`. This is normal and expected:

- The formatter ensures consistent code style across all Nix files
- These changes are typically whitespace and formatting adjustments
- The `build.sh` script automatically runs `git add .` before building
- Review changes with `git diff` before committing

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

**Flake warnings about overrides**

- Warnings like `input 'X' has an override for a non-existent input 'Y'` are typically harmless
- These occur when inputs try to override dependencies that aren't directly used
- Can be safely ignored unless they cause build failures

**Build failures with `abort-on-warn`**

- This configuration enforces warning-free code
- Any warning will cause the build to fail
- Fix the warning or temporarily disable with `--no-abort-on-warn` for debugging

**Git tree dirty warnings**

- Normal when you have uncommitted changes
- The warning doesn't prevent building
- Use `git status` to see what's modified

### Debug Commands

```bash
# Interactive module exploration
nix repl /home/vx/nixos
> :p flake.modules.nixos

# Check specific values
nix eval .#nixosConfigurations.system76.config.networking.hostName

# Verbose build trace
nix build --show-trace .#nixosConfigurations.system76.config.system.build.toplevel

# Debug module loading (check if a module is being imported)
nix eval .#debug.allModules | jq | grep "module-name"

# List all available flake outputs
nix flake show --json | jq
```

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

## Development Shell

The development shell (via `nix develop`) provides:

- `nixfmt-rfc-style` - Nix code formatter
- `nil` - Nix LSP for IDE integration
- `nix-tree` - Dependency exploration
- `nix-diff` - Generation comparison
- `jq`/`yq` - JSON/YAML processing
- `treefmt` - Multi-language formatter with:
  - `nixfmt` - Nix files (enabled)
  - `prettier` - JSON, YAML, Markdown files (enabled)
  - `shfmt` - Shell scripts (enabled)
- `generation-manager` - System generation management utility

Shell includes a helpful welcome message with common commands.

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
  - `nix fmt:*` - Code formatting commands
  - `nix flake check:*` - Flake validation commands
  - `nix log:*` - Build log inspection commands
  - `nix-shell:*` - Nix shell environment commands
  - `nix develop:*` - Development shell commands
  - `mcp__sequential-thinking__sequentialthinking` - Sequential thinking tool for complex problems
  - `mcp__context7__resolve-library-id` - Library ID resolution for documentation
  - `mcp__context7__get-library-docs` - Fetch library documentation
