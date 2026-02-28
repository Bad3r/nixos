# Espanso Text Expander Module

## Overview

The espanso module provides declarative configuration for the cross-platform text expander. It uses Home Manager's `services.espanso` module with sensible defaults and common match patterns.

## Quick Start

### Enable in Home Manager Configuration

The module is auto-imported when included in your Home Manager modules list:

```nix
{
  imports = [
    config.flake.homeManagerModules.apps.espanso
  ];
}
```

This automatically enables espanso with:

- Both X11 and Wayland support (auto-detection based on `$WAYLAND_DISPLAY`)
- Notifications disabled (less intrusive)
- Common date/time triggers (`:date`, `:time`, `:now`, `:isodate`)
- Development snippets (`:shebang`, `:todo`, `:fixme`)

### Default Triggers

Once enabled, the following triggers are available:

| Trigger       | Output            | Example                                             |
| ------------- | ----------------- | --------------------------------------------------- |
| `:date`       | Current date      | `2025-10-08`                                        |
| `:time`       | Current time      | `14:30`                                             |
| `:now`        | Date and time     | `2025-10-08 14:30`                                  |
| `:isodate`    | ISO 8601 format   | `2025-10-08T14:30:00+0000`                          |
| `:shebang`    | Bash shebang      | `#!/usr/bin/env bash`                               |
| `:shebangnix` | Nix-shell shebang | `#!/usr/bin/env nix-shell`<br>`#!nix-shell -i bash` |
| `:todo`       | TODO comment      | `# TODO: `                                          |
| `:fixme`      | FIXME comment     | `# FIXME: `                                         |

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

Both X11 and Wayland support are enabled by default on Linux. The module:

- Configures `x11Support = true` and `waylandSupport = true`
- Sets `package-wayland = pkgs.espanso-wayland`
- Creates a wrapper script that checks `$WAYLAND_DISPLAY` at runtime
- Automatically launches the correct binary based on your graphical session

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
3. Test with `:espanso` trigger (built-in test)
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

### In Dendritic Configuration

Import in your home-manager configuration:

```nix
# In configurations/homeManager/<username>/default.nix
{
  imports = [
    config.flake.homeManagerModules.apps.espanso
  ];

  # Override defaults as needed
  services.espanso.matches.personal = {
    matches = [
      # Your custom matches
    ];
  };
}
```

### Module Location

The espanso module is auto-discovered from:

- Source: `modules/hm-apps/espanso.nix`
- Export: `flake.homeManagerModules.apps.espanso`

## References

- **Official Documentation**: https://espanso.org/docs/
- **Configuration Guide**: https://espanso.org/docs/configuration/basics/
- **Matches Guide**: https://espanso.org/docs/matches/basics/
- **Variables Reference**: https://espanso.org/docs/matches/extensions/
- **nixpkgs Package**: `pkgs/by-name/es/espanso/package.nix`
- **Home Manager Module**: `/data/git/nix-community-home-manager/modules/services/espanso.nix`
