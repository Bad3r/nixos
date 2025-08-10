# Dendritic Pattern Guide for NixOS Configuration

## What is the Dendritic Pattern?

The dendritic pattern is a configuration architecture that mimics organic growth patterns found in nature (like dendrites in neurons or tree branches). In this NixOS configuration:

- **Files grow organically**: Add, move, or rename files without updating imports
- **Automatic discovery**: All `.nix` files in `modules/` are automatically imported
- **No explicit imports**: Modules never use literal path imports
- **Namespace-based composition**: Modules contribute to shared namespaces that compose naturally

## Core Principles

### 1. No Explicit Imports
```nix
# ❌ WRONG - Never do this:
{ ... }:
{
  imports = [ ./some-module.nix ];
}

# ✅ CORRECT - Use namespace references:
{ config, ... }:
{
  flake.modules.nixos.pc = {
    imports = [ config.flake.modules.nixos.base ];
  };
}
```

### 2. Automatic Module Discovery
Every `.nix` file in the `modules/` directory is automatically imported by `import-tree`. This means:
- Adding a new file immediately makes it available
- Removing a file removes its functionality
- Moving files doesn't break references

### 3. Metadata-Driven Configuration
All configurable values live in `flake.meta`:

```nix
# ❌ WRONG - Hardcoded values:
users.users.vx = {
  isNormalUser = true;
};

# ✅ CORRECT - Metadata-driven:
users.users.${config.flake.meta.owner.username} = {
  isNormalUser = true;
};
```

## Directory Structure

```
modules/
├── meta/              # Metadata and configuration options
│   ├── owner.nix      # Owner information and system metadata
│   └── flake-output.nix # Option declarations
├── base/              # Core system (every NixOS system needs these)
│   ├── boot.nix       # Boot configuration
│   ├── locale.nix     # Timezone and locale
│   ├── networking.nix # Core networking
│   ├── nix.nix        # Nix daemon configuration
│   ├── ssh.nix        # SSH configuration
│   └── users.nix      # User accounts
├── pc/                # Desktop/PC configuration
│   ├── audio.nix      # Audio (PipeWire)
│   ├── bluetooth.nix  # Bluetooth support
│   ├── fonts.nix      # Font packages
│   └── graphics.nix   # GPU drivers
├── workstation/       # Development workstation
│   ├── docker.nix     # Container tools
│   ├── databases.nix  # Database servers
│   └── languages.nix  # Programming languages
├── desktop/           # Desktop environments
│   └── kde.nix        # KDE Plasma
├── applications/      # User applications
│   ├── browsers.nix   # Web browsers
│   └── editors.nix    # Text editors
├── home/              # Home-manager integration
│   ├── base.nix       # Base home configuration
│   └── gui.nix        # GUI applications
└── hosts/             # Host-specific (NOT auto-imported)
    └── system76/      # System76 laptop configuration
```

## Namespace Hierarchy

### System-Level Namespaces

#### `flake.modules.nixos.base`
Core system configuration that ALL NixOS systems need:
- User accounts
- Timezone/locale
- Nix daemon settings
- Core networking
- Boot configuration

```nix
# modules/base/locale.nix
{ config, ... }:
{
  flake.modules.nixos.base = {
    time.timeZone = config.flake.meta.system.timezone;
    i18n.defaultLocale = config.flake.meta.system.locale;
  };
}
```

#### `flake.modules.nixos.pc`
Configuration for personal computers (desktops/laptops):
- Audio subsystem
- Bluetooth
- Fonts
- Graphics drivers
- Printing

```nix
# modules/pc/audio.nix
{ ... }:
{
  flake.modules.nixos.pc = {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };
}
```

#### `flake.modules.nixos.workstation`
Development workstation configuration:
- Development tools
- Language toolchains
- Databases
- Virtualization

```nix
# modules/workstation/docker.nix
{ config, ... }:
{
  flake.modules.nixos.workstation = {
    virtualisation.docker = {
      enable = config.flake.meta.features.virtualization;
    };
  };
}
```

#### `flake.modules.nixos."named-module"`
Specialized modules that can be explicitly imported:

```nix
# modules/desktop/kde.nix
{ ... }:
{
  flake.modules.nixos."kde-plasma" = { pkgs, ... }: {
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm.enable = true;
  };
}
```

### Home-Manager Namespaces

#### `flake.modules.homeManager.base`
Base home-manager configuration for all users:
- Shell configuration
- Git settings
- Core utilities

#### `flake.modules.homeManager.gui`
GUI application configuration:
- Terminal emulators
- Browsers
- Editors

## Module Patterns

### Basic Module Structure
```nix
# Module: category/name.nix
# Purpose: Brief description of what this module does
# Namespace: flake.modules.nixos.pc (or appropriate namespace)
# Dependencies: What this module needs to work

{ config, lib, pkgs, ... }:
{
  flake.modules.nixos.pc = { ... }: {
    # Module configuration
  };
}
```

### Using Metadata
```nix
{ config, ... }:
{
  flake.modules.nixos.base = {
    users.users.${config.flake.meta.owner.username} = {
      description = config.flake.meta.owner.name;
      openssh.authorizedKeys.keys = config.flake.meta.owner.sshKeys;
    };
  };
}
```

### Conditional Features
```nix
{ config, lib, ... }:
{
  flake.modules.nixos.workstation = lib.mkIf config.flake.meta.features.gaming {
    programs.steam.enable = true;
  };
}
```

### Named Modules for Optional Features
```nix
# modules/applications/vscode.nix
{ ... }:
{
  flake.modules.nixos."vscode" = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.vscode ];
  };
}

# Used in host configuration:
# imports = [ config.flake.modules.nixos.vscode ];
```

## Adding a New Module

### Step 1: Choose the Right Location
- Is it needed by ALL systems? → `base/`
- Is it for desktop systems? → `pc/`
- Is it for development? → `workstation/`
- Is it optional? → Create a named module

### Step 2: Create the Module File
```nix
# modules/pc/newfeature.nix
{ config, ... }:
{
  flake.modules.nixos.pc = {
    # Your configuration
  };
}
```

### Step 3: Use Metadata
Replace hardcoded values with metadata references:
```nix
networking.hostName = config.flake.meta.system.hostName;
```

### Step 4: Test
```bash
# The module is automatically discovered - just build
nix build .#nixosConfigurations.system76.config.system.build.toplevel
```

## Host Configuration

Host configurations use the composed modules:

```nix
# modules/hosts/system76/default.nix
{ config, ... }:
{
  configurations.nixos.system76.module = {
    imports = with config.flake.modules.nixos; [
      efi           # EFI boot
      workstation   # Development setup
      nvidia-gpu    # NVIDIA graphics
      kde-plasma    # KDE desktop
    ];
    
    # Host-specific overrides
    networking.hostName = "system76";
    system.stateVersion = config.flake.meta.system.stateVersion;
  };
}
```

## Common Patterns

### Pattern: Extensible Lists
```nix
# modules/base/packages.nix
{ config, ... }:
{
  flake.modules.nixos.base = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      git
      vim
      wget
    ];
  };
}

# modules/pc/packages.nix - Adds to the list
{ ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      firefox
      kate
    ];
  };
}
```

### Pattern: Overlay Configuration
```nix
# Multiple modules can contribute to the same namespace
# modules/pc/audio.nix
flake.modules.nixos.pc = {
  services.pipewire.enable = true;
};

# modules/pc/bluetooth.nix
flake.modules.nixos.pc = {
  hardware.bluetooth.enable = true;
};
```

### Pattern: Pipe Operators
Use pipe operators for elegant data transformation:
```nix
{ lib, config, ... }:
{
  flake.modules.nixos.base = {
    networking.hosts = 
      config.flake.nixosConfigurations
      |> lib.filterAttrs (name: cfg: cfg.config.networking.hostName != null)
      |> lib.mapAttrs (name: cfg: [ cfg.config.networking.hostName ]);
  };
}
```

## Troubleshooting

### Module Not Found
**Problem**: Added a new module but it's not being recognized.
**Solution**: 
- Ensure the file has `.nix` extension
- Check that it's in the `modules/` directory
- Run `nix flake show` to see all detected modules

### Infinite Recursion
**Problem**: Getting infinite recursion errors.
**Solution**:
- Don't reference config values in imports
- Use function arguments for module configuration
- Check for circular dependencies between modules

### Option Already Defined
**Problem**: "The option `...` is already declared"
**Solution**:
- Multiple modules are trying to set the same option
- Use `lib.mkForce` or `lib.mkDefault` for priorities
- Consider using `lib.mkMerge` for lists

### Metadata Not Available
**Problem**: `config.flake.meta.owner` is null or undefined
**Solution**:
- Ensure `modules/meta/owner.nix` exists
- Check that metadata is defined before use
- Use `lib.mkIf` for conditional access

## Best Practices

1. **Always use metadata** instead of hardcoding values
2. **Document your modules** with header comments
3. **Keep modules focused** on a single concern
4. **Use meaningful namespaces** that indicate the module's purpose
5. **Test incrementally** after adding new modules
6. **Prefer composition** over complex conditionals
7. **Use named modules** for optional features

## Migration Checklist

When migrating existing configuration:

- [ ] Replace all hardcoded usernames with `${config.flake.meta.owner.username}`
- [ ] Move all configurable values to `flake.meta`
- [ ] Ensure modules use proper namespaces
- [ ] Remove all explicit imports
- [ ] Split large modules into focused components
- [ ] Add documentation headers to all modules
- [ ] Test with different metadata values

## Examples from This Repository

### Metadata Usage
```nix
# modules/base/users.nix
users.users.${config.flake.meta.owner.username} = {
  description = config.flake.meta.owner.name;
  openssh.authorizedKeys.keys = config.flake.meta.owner.sshKeys;
};
```

### Namespace Composition
```nix
# Multiple modules contribute to pc namespace
# modules/pc/audio.nix → flake.modules.nixos.pc
# modules/pc/bluetooth.nix → flake.modules.nixos.pc
# modules/pc/fonts.nix → flake.modules.nixos.pc
# All merge automatically into a single configuration
```

### Named Module Import
```nix
# modules/desktop/kde.nix defines flake.modules.nixos."kde-plasma"
# Used in: modules/hosts/system76/default.nix
imports = [ config.flake.modules.nixos."kde-plasma" ];
```

## Resources

- [flake-parts documentation](https://flake.parts)
- [import-tree](https://github.com/vc/import-tree)
- Original pattern inspiration: mightyiam/infra