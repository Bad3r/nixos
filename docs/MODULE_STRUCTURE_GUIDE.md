# NixOS Module Structure Guide

This guide explains the correct patterns for writing modules in this flake-parts + import-tree based NixOS configuration.

## Overview

This repository uses:

- **flake-parts**: For modular flake composition
- **import-tree**: For automatic module discovery (all `.nix` files in `modules/` are imported)
- **Namespace pattern**: Modules export to `flake.nixosModules.*` or `flake.homeManagerModules.*`

## Module Structure Patterns

### Pattern 1: Module That Needs Packages

Use this when your module needs to access `pkgs`:

```nix
# modules/my-feature.nix
{ config, lib, ... }:
{
  flake.nixosModules.my-feature = { pkgs, ... }: {
    # Your NixOS configuration here
    environment.systemPackages = with pkgs; [
      some-package
    ];

    services.some-service.enable = true;
  };
}
```

**Key points:**

- The module file takes `{ config, lib, ... }` (NO pkgs at this level)
- The value assigned to `flake.nixosModules.my-feature` is a FUNCTION that takes `{ pkgs, ... }`
- This module can be imported by other modules using `config.flake.nixosModules.my-feature`

### Pattern 2: Module Contributing to Multiple Namespaces

```nix
# modules/feature-with-home-manager.nix
{ config, lib, pkgs, ... }:
{
  flake.nixosModules.my-feature = {
    # System-level configuration
    services.my-service.enable = true;
  };

  flake.homeManagerModules.base = {
    # User-level configuration
    programs.my-program.enable = true;
  };
}
```

### Pattern 3: Module Without Package Dependencies

If your module doesn't need `pkgs`:

```nix
# modules/simple-config.nix
{
  flake.nixosModules.pc = {
    time.timeZone = "America/New_York";
    i18n.defaultLocale = "en_US.UTF-8";
  };
}
```

### Pattern 4: Module That Extends Existing Namespaces

```nix
# modules/extends-pc.nix
{ lib, ... }:
{
  flake.nixosModules.pc = lib.mkIf true {
    services.some-service.enable = true;
  };
}
```

## Common Pitfalls

### ❌ WRONG: Using pkgs from Outer Scope

```nix
# DON'T DO THIS!
{ config, lib, pkgs, ... }:  # ← pkgs is NOT available in flake-parts context
{
  flake.nixosModules.my-feature = {  # ← This needs to be a function to access pkgs
    environment.systemPackages = with pkgs; [ ... ];  # ← pkgs is undefined!
  };
}
```

The `pkgs` parameter at the module file level is NOT populated in flake-parts context.

### ✅ CORRECT: Module Value as Function

```nix
# When your module needs pkgs, make the value a function
{ config, lib, ... }:  # ← No pkgs here - it's not available
{
  flake.nixosModules.my-feature = { pkgs, ... }: {  # ← Function that takes pkgs
    environment.systemPackages = with pkgs; [ ... ];  # ← Now pkgs is available
  };
}
```

### ✅ CORRECT: Module Without pkgs

```nix
# When your module doesn't need pkgs, use direct attribute set
{ config, lib, ... }:
{
  flake.nixosModules.my-feature = {
    services.some-service.enable = true;
    networking.hostName = "example";
  };
}
```

## How Modules Are Used

### 1. Automatic Import

All `.nix` files in `modules/` are automatically imported by import-tree (except files starting with `_`).

### 2. Module Registration

Each module registers itself under `flake.nixosModules.*` or `flake.homeManagerModules.*`.

### 3. Module Composition

Modules can import each other:

```nix
# modules/composite.nix
{ config, ... }:
{
  flake.nixosModules.my-composite = {
    imports = with config.flake.nixosModules; [
      base-packages
      my-feature
      another-feature
    ];

    # Additional configuration
  };
}
```

### 4. Host Configuration

Host configurations use the registered modules:

```nix
# modules/nixosConfigurations/my-host.nix
{ config, ... }:
{
  configurations.nixos.my-host.module = {
    imports = [
      config.flake.nixosModules.workstation
      config.flake.nixosModules.my-composite
    ];

    networking.hostName = "my-host";
  };
}
```

## Module Types

### System Modules

- Namespace: `flake.nixosModules.*`
- Purpose: NixOS system configuration
- Example: services, packages, hardware config

### Home Manager Modules

- Namespace: `flake.homeManagerModules.*`
- Sub-namespaces: `base` (CLI), `gui` (graphical)
- Purpose: User environment configuration
- Example: dotfiles, user packages, desktop settings

### Host Modules

- Namespace: `configurations.nixos.<name>.module`
- Purpose: Define complete system configurations
- Transformed into flake.nixosConfigurations by modules/configurations/nixos.nix

## Best Practices

1. **One Purpose Per Module**: Keep modules focused on a single feature or concern
2. **Clear Naming**: Use descriptive names that indicate the module's purpose
3. **Document Dependencies**: Comment when a module depends on others
4. **Use Namespaces**: Organize related configurations under common namespaces
5. **Avoid Deep Nesting**: Keep the module structure relatively flat

## Debugging Tips

### Check Module Exports

```bash
nix repl /home/vx/nixos
> :p flake.nixosModules
```

### Verify Module Structure

```bash
nix eval /home/vx/nixos#nixosConfigurations.system76.config.environment.systemPackages
```

### Common Errors

1. **"attribute 'pkgs' missing"**: Module needs `pkgs` in its parameter list
2. **"expected a set but got a function"**: Remove function wrapper from flake.nixosModules assignment
3. **"infinite recursion"**: Check for circular imports between modules

## Migration from Traditional NixOS

If migrating from a traditional NixOS configuration:

1. Split configuration into logical modules
2. Each module should export to `flake.nixosModules.<name>`
3. Use the patterns above based on your needs
4. Test incrementally by importing modules one at a time
