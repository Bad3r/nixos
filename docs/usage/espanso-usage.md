# Espanso Text Expander Module

## Overview

The espanso module provides declarative configuration for the cross-platform text expander. It uses Home Manager's `services.espanso` module with sensible defaults and common match patterns.

## Quick Start

### Enable espanso

Two modules cooperate behind a single system-level toggle:

- `flake.nixosModules.apps.espanso` (source: `modules/apps/espanso.nix`) defines
  the option `services.espanso.extended.enable` (default `false`).
- `flake.homeManagerModules.apps.espanso` (source: `modules/hm-apps/espanso.nix`)
  reads that toggle from `osConfig` and configures `services.espanso` only when
  it is `true`.

Importing the Home Manager module alone does nothing: the toggle must be on at
the system level. On hosts that use the common baseline this is already wired:

- `modules/hosts/common/home-manager-apps.nix` adds `espanso` to the shared
  Home Manager app modules.
- `modules/hosts/common/apps-enable.nix` sets
  `services.espanso.extended.enable = true` at the default-on baseline
  (`lib.mkOverride 1100`).

So common hosts get espanso enabled by default. To opt out on a host, set
`services.espanso.extended.enable = false`. To enable it on a host that does not
use the baseline, import `flake.nixosModules.apps.espanso` and set the toggle
true at the system level.

When enabled, espanso starts with:

- Both X11 and Wayland support (Home Manager defaults on Linux; runtime selection based on `$WAYLAND_DISPLAY`)
- Notifications disabled (less intrusive)
- Common date/time triggers (`:date`, `:time`, `:now`, `:isodate`)
- Development snippets (`:shebang`, `:shebangnix`, `:todo`, `:fixme`)
- A `:test` smoke-test trigger that expands to `test 1.2.3`

### Default Triggers

Once enabled, the following triggers are available:

<!-- dprint-ignore-start -->

| Trigger       | Output            | Example                                             |
| ------------- | ----------------- | --------------------------------------------------- |
| `:test`       | Smoke-test string | `test 1.2.3`                                        |
| `:date`       | Current date      | `2025-10-08`                                        |
| `:time`       | Current time      | `14:30`                                             |
| `:now`        | Date and time     | `2025-10-08 14:30`                                  |
| `:isodate`    | ISO 8601 format   | `2025-10-08T14:30:00+0000`                          |
| `:shebang`    | Bash shebang      | `#!/usr/bin/env bash`                               |
| `:shebangnix` | Nix-shell shebang | `#!/usr/bin/env nix-shell`<br>`#!nix-shell -i bash` |
| `:todo`       | TODO comment      | `# TODO: `                                          |
| `:fixme`      | FIXME comment     | `# FIXME: `                                         |

<!-- dprint-ignore-end -->

## Customization

### Adding Custom Matches

Extend the default matches with your own patterns:

```nix
{
  services.espanso.matches = {
    # Add to existing matches
    email = {
      matches = [
        {
          trigger = ":email";
          replace = "your.email@example.com";
        }
        {
          trigger = ":work";
          replace = "work.email@company.com";
        }
      ];
    };

    # Code snippets
    coding = {
      matches = [
        {
          trigger = ":func";
          replace = "function $1() {\n  $0\n}";
        }
        {
          trigger = ":lambda";
          replace = "lambda x: x";
        }
      ];
    };
  };
}
```

### App-Specific Configurations

Configure espanso behavior per application:

```nix
{
  services.espanso.configs = {
    # Global settings
    default = {
      show_notifications = true;  # Override default
    };

    # VSCode-specific
    vscode = {
      filter_title = "Visual Studio Code$";
      backend = "Clipboard";  # Better compatibility
    };

    # Terminal-specific
    terminal = {
      filter_class = "Alacritty|kitty|wezterm";
      backend = "Inject";
    };
  };
}
```

### Advanced Variables

Espanso supports various variable types:

```nix
{
  services.espanso.matches.advanced = {
    matches = [
      # Form with user input
      {
        trigger = ":greet";
        replace = "Hello {{name}}!";
        vars = [
          {
            name = "name";
            type = "form";
            params = {
              layout = "Name: [[name]]";
            };
          }
        ];
      }

      # Shell command output
      {
        trigger = ":ip";
        replace = "{{output}}";
        vars = [
          {
            name = "output";
            type = "shell";
            params = {
              cmd = "curl -s ifconfig.me";
            };
          }
        ];
      }

      # Clipboard content
      {
        trigger = ":clip";
        replace = "{{clipboard}}";
        vars = [
          {
            name = "clipboard";
            type = "clipboard";
          }
        ];
      }
    ];
  };
}
```

### Regex Triggers

Use regex for more flexible matching:

```nix
{
  services.espanso.matches.regex = {
    matches = [
      {
        regex = ":hi(?P<person>\\w+)";
        replace = "Hello {{person}}!";
      }
      {
        regex = ":math(?P<expr>[0-9+\\-*/]+)";
        replace = "{{result}}";
        vars = [
          {
            name = "result";
            type = "shell";
            params = {
              cmd = "echo \"{{expr}}\" | bc";
            };
          }
        ];
      }
    ];
  };
}
```

## Display Server Configuration

### Default Behavior (Recommended)

Home Manager's `services.espanso` module enables both X11 and Wayland support by
default on Linux. Its upstream module:

- Defaults `x11Support = true` and `waylandSupport = true` on Linux
- Defaults `package-wayland = pkgs.espanso-wayland` when Wayland support is on
- Creates a wrapper script that checks `$WAYLAND_DISPLAY` at runtime
- Automatically launches the correct binary based on your graphical session

This repository's Home Manager app module leaves those display-server defaults
in place; it adds repo-specific configs, matches, and service restart policy
only after `services.espanso.extended.enable` is true.

### Optimizing Closure Size

If you only use one display server, disable the unused support:

```nix
{
  # Wayland-only
  services.espanso = {
    x11Support = false;
    waylandSupport = true;
  };

  # X11-only
  services.espanso = {
    x11Support = true;
    waylandSupport = false;
  };
}
```

### Custom Package

Override the espanso package if needed:

```nix
{
  services.espanso = {
    package = pkgs.espanso;  # X11 variant
    package-wayland = pkgs.espanso-wayland;  # Wayland variant
  };
}
```

## Service Management

The module automatically configures systemd user service (Linux) or launchd agent (macOS):

```bash
# Check service status
systemctl --user status espanso

# Restart service
systemctl --user restart espanso

# View logs
journalctl --user -u espanso -f
```

## Configuration Files

Generated YAML files are located at:

- `~/.config/espanso/config/*.yml` - Configuration files
- `~/.config/espanso/match/*.yml` - Match files

These are managed declaratively via Nix. Manual edits will be overwritten on Home Manager activation.

## Troubleshooting

### Espanso Not Triggering

1. Verify service is running: `systemctl --user status espanso`
2. Check logs: `journalctl --user -u espanso`
3. Test with the `:test` trigger (defined in this repo, expands to `test 1.2.3`)
4. Ensure correct backend for your application (try `backend = "Clipboard"`)

### Wayland Clipboard Issues

For multi-user setups on Wayland, you may need additional permissions:

```bash
# Find Wayland directory
echo $XDG_RUNTIME_DIR

# Grant permissions (example for user 'username')
sudo usermod -a -G username espanso
chmod g+rwx $XDG_RUNTIME_DIR
chmod g+w $XDG_RUNTIME_DIR/wayland-0
```

### Application Compatibility

Some applications require clipboard backend:

```nix
{
  services.espanso.configs.incompatible-app = {
    filter_title = "AppName$";
    backend = "Clipboard";
  };
}
```

## Integration with This Repository

### Common-baseline hosts

Hosts whose registry entry has `shareCommon = true` already receive espanso
through the common host modules:

- `modules/hosts/common/home-manager-apps.nix` appends `espanso` to
  `home-manager.extraAppImports` and adds `flake.homeManagerModules.apps.espanso`
  to shared modules.
- `modules/hosts/common/apps-enable.nix` sets
  `services.espanso.extended.enable = true` at `lib.mkOverride 1100`.

For those hosts, do not add a separate Home Manager import. Customize
`services.espanso.matches` in Home Manager configuration, or opt out by setting
`services.espanso.extended.enable = false`.

### Hosts outside the common baseline

A host that does not use `hosts-common` needs a flake-parts module that pushes
both the NixOS option module and Home Manager app import into the host module:

```nix
{ config, lib, ... }:
let
  espansoModule = config.flake.nixosModules.apps.espanso;
in
{
  configurations.nixos.<hostName>.module = _: {
    imports = [ espansoModule ];

    services.espanso.extended.enable = true;
    home-manager.extraAppImports = lib.mkAfter [ "espanso" ];
  };
}
```

`home-manager.extraAppImports` is defined by `flake.nixosModules.base`, so the
host must already import that aggregate. Standard NixOS configurations in this
repository do.

### Module locations

The espanso modules are auto-discovered from:

- NixOS source: `modules/apps/espanso.nix`
- NixOS export: `flake.nixosModules.apps.espanso`
- Home Manager source: `modules/hm-apps/espanso.nix`
- Home Manager export: `flake.homeManagerModules.apps.espanso`

## References

- **Official Documentation**: https://espanso.org/docs/
- **Configuration Guide**: https://espanso.org/docs/configuration/basics/
- **Matches Guide**: https://espanso.org/docs/matches/basics/
- **Variables Reference**: https://espanso.org/docs/matches/extensions/
- **nixpkgs Package**: `pkgs/by-name/es/espanso/package.nix`
- **Home Manager Module**: `/data/git/nix-community-home-manager/modules/services/espanso.nix`
