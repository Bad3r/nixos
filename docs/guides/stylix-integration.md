# Stylix Integration

Stylix themes both NixOS and Home Manager applications in this repository, and each Stylix target exists in only one of those contexts.

## Overview

[Stylix](https://github.com/nix-community/stylix) provides automatic, consistent theming across NixOS and Home Manager applications using base16 color schemes. This repository integrates Stylix at both the system (NixOS) and user (Home Manager) levels. The `stylix` flake input is pinned to `github:Bad3r/stylix/master`, a maintained fork of nix-community/stylix.

The integration is configured in:

- `modules/stylix/stylix.nix` -- NixOS and Home Manager Stylix configuration
  (exports `flake.nixosModules.base` and
  `flake.homeManagerModules.{base,apps.stylix-gui}`)
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
nix eval .#nixosConfigurations.songbird.options.stylix.targets --apply builtins.attrNames

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
# Correct NixOS app module (mirrors modules/apps/dunst/nixos.nix)
_:
let
  DunstModule =
    { config, lib, pkgs, ... }:
    let
      cfg = config.programs.dunst.extended;
    in
    {
      options.programs.dunst.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dunst.";
        };

        package = lib.mkPackageOption pkgs "dunst" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        # NO stylix.targets.dunst.enable here -- it's HM-only
      };
    };
in
{
  flake.nixosModules.apps.dunst = DunstModule;
}
```

### Home Manager Modules (`modules/apps/<name>/home.nix`)

1. **Do NOT manually set `stylix.targets.*`** -- let `autoEnable` handle it
2. Only set targets if you need to **disable** theming for a specific app
3. If you must set a target, use appropriate priority

```nix
# Correct HM app module -- let autoEnable work
# (mirrors modules/apps/fzf/home.nix, abridged)
{
  flake.homeManagerModules.apps.fzf =
    { osConfig, lib, ... }:
    let
      enabled = lib.attrByPath [ "programs" "fzf" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf enabled {
        programs.fzf.enable = true;
        # Stylix will automatically enable stylix.targets.fzf
        # because programs.fzf.enable = true
      };
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

## Tray Icon Theming

Tray icon behavior is host/protocol dependent and can diverge from Stylix target
settings. Use the dedicated guide for runtime protocol detection, i3/i3bar tray
ownership, and package-level remediation patterns:

- [Tray Icon Theming (i3/i3bar)](tray-icon-theming.md)

## Related Documentation

- [`docs/architecture/01-pattern-overview.md`](../architecture/01-pattern-overview.md) -- module discovery and aggregator patterns
- [`docs/architecture/04-home-manager.md`](../architecture/04-home-manager.md) -- how Home Manager modules are composed
- [Apps Module Style Guide](apps-module-style-guide.md) -- per-app module authoring conventions
- [Stylix troubleshooting](stylix-troubleshooting.md) -- common pitfalls and debugging commands
- [Stylix Documentation](https://nix-community.github.io/stylix/) -- upstream reference
- [Tray Icon Theming (i3/i3bar)](tray-icon-theming.md) -- protocol classification and tray icon remediation on this host
