# Stylix Integration

This document covers how Stylix theming integrates with the Dendritic Pattern and the key constraints module authors must understand.

## Overview

[Stylix](https://github.com/danth/stylix) provides automatic, consistent theming across NixOS and Home Manager applications using base16 color schemes. This repository integrates Stylix at both the system (NixOS) and user (Home Manager) levels.

The integration is configured in:

- `modules/theming/stylix.nix` -- NixOS-level Stylix configuration
- Individual app modules -- may interact with Stylix targets

## Key Concept: NixOS vs Home Manager Targets

Stylix exposes `stylix.targets.<app>.enable` options, but **these targets exist in different contexts**:

| Context      | Example Targets                                            | Where Defined             |
| ------------ | ---------------------------------------------------------- | ------------------------- |
| NixOS        | `console`, `grub`, `plymouth`, `gtk`, `lightdm`, `nixvim`  | System-level applications |
| Home Manager | `dunst`, `rofi`, `mpv`, `alacritty`, `kitty`, `fzf`, `bat` | User-level applications   |

**Critical Rule**: A NixOS module cannot set Home Manager-only targets, and vice versa. Attempting to do so results in undefined option errors.

To inspect available targets in each context:

```bash
# NixOS targets
nix eval .#nixosConfigurations.system76.options.stylix.targets --apply builtins.attrNames

# Home Manager targets (via the HM module system)
# These are only available within Home Manager module evaluation
```

## The autoEnable Mechanism

Stylix provides `stylix.autoEnable` (default: `true`) which automatically enables theming for all detected applications. When `autoEnable` is true:

1. Stylix checks if an application's program option is enabled (e.g., `programs.fzf.enable`)
2. If enabled, Stylix automatically sets `stylix.targets.<app>.enable = true`

**Important**: Stylix's `autoEnable` does **not** detect whether an application is installed via `environment.systemPackages`. It only responds to program-specific options like `programs.<app>.enable`.

### Priority and Overrides

Stylix sets target enables with a specific priority. Using `lib.mkDefault true` in app modules can accidentally override user preferences:

```nix
# BAD: This overrides user's stylix.autoEnable = false setting
stylix.targets.fzf.enable = lib.mkDefault true;

# GOOD: Let Stylix's autoEnable handle it automatically
# (simply omit the line)
```

## Best Practices for Module Authors

### NixOS App Modules (`modules/apps/`)

1. **Do NOT set `stylix.targets.*` options** -- these are typically Home Manager targets
2. Focus on `environment.systemPackages` and system-level configuration
3. Let Home Manager modules handle user-level theming

```nix
# Correct NixOS app module
{
  flake.nixosModules.apps.dunst =
    { pkgs, lib, config, ... }:
    let
      cfg = config.programs.dunst.extended;
    in
    {
      options.programs.dunst.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dunst notification daemon.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ pkgs.dunst ];
        # NO stylix.targets.dunst.enable here -- it's HM-only
      };
    };
}
```

### Home Manager Modules (`modules/hm-apps/`)

1. **Do NOT manually set `stylix.targets.*`** -- let `autoEnable` handle it
2. Only set targets if you need to **disable** theming for a specific app
3. If you must set a target, use appropriate priority

```nix
# Correct HM app module -- let autoEnable work
{
  flake.homeManagerModules.apps.fzf =
    { lib, ... }:
    {
      programs.fzf.enable = true;
      # Stylix will automatically enable stylix.targets.fzf
      # because programs.fzf.enable = true
    };
}

# Only if you need to DISABLE theming:
{
  flake.homeManagerModules.apps.some-app =
    { lib, ... }:
    {
      programs.some-app.enable = true;
      stylix.targets.some-app.enable = false;  # Explicitly disable
    };
}
```

## Common Pitfalls

### Pitfall 1: Setting HM Targets in NixOS Modules

```nix
# WRONG -- dunst target only exists in Home Manager
flake.nixosModules.apps.dunst = { ... }: {
  stylix.targets.dunst.enable = lib.mkDefault true;  # ERROR: undefined option
};
```

This causes evaluation errors unless `_module.check = false` is set, which masks the problem.

### Pitfall 2: Redundant Target Enables

```nix
# WRONG -- redundant and potentially buggy
flake.homeManagerModules.apps.fzf = { lib, ... }: {
  programs.fzf.enable = true;
  stylix.targets.fzf.enable = lib.mkDefault true;  # Redundant!
};
```

Stylix already enables this automatically. The `lib.mkDefault` can override user's `stylix.autoEnable = false`.

### Pitfall 3: Using \_module.check = false

Never use `_module.check = false` to silence option errors. This masks real problems:

```nix
# WRONG -- hides undefined option errors
configurations.nixos.myhost.module = {
  _module.check = false;  # Don't do this
  imports = [ ... ];
};
```

Instead, fix the root cause by ensuring options are only set in their valid context.

## Debugging Stylix Issues

### Check Which Targets Exist

```bash
# List NixOS stylix targets
nix eval .#nixosConfigurations.system76.options.stylix.targets \
  --apply builtins.attrNames 2>/dev/null | tr ',' '\n' | tr -d '[]" '
```

### Verify Target State

```bash
# Check if a specific target is enabled in the final config
nix eval .#nixosConfigurations.system76.config.stylix.targets.console.enable
```

### Trace autoEnable Behavior

If theming isn't applying, verify:

1. `stylix.autoEnable` is `true` (or not explicitly `false`)
2. The corresponding `programs.<app>.enable` is `true`
3. The target exists in the current context (NixOS vs HM)

## Related Documentation

- [`docs/architecture/01-pattern-overview.md`](../architecture/01-pattern-overview.md) -- module discovery and aggregator patterns
- [`docs/architecture/04-home-manager.md`](../architecture/04-home-manager.md) -- how Home Manager modules are composed
- [Apps Module Style Guide](apps-module-style-guide.md) -- per-app module authoring conventions
- [Stylix Documentation](https://danth.github.io/stylix/) -- upstream reference
