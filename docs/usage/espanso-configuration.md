# Espanso Configuration

Per-application behavior, display-server support, and the package come from Home Manager's `services.espanso`; enabling espanso is in [Espanso usage](espanso-usage.md).
The settings are in the [espanso configuration guide](https://espanso.org/docs/configuration/basics/).

## App-Specific Configurations

Each attribute of `services.espanso.configs` is one config file, filtered to the applications it matches:

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

## Display Servers

Home Manager's `services.espanso` module enables both X11 and Wayland support by default on Linux:

- It defaults `x11Support = true` and `waylandSupport = true` on Linux.
- It defaults `package-wayland = pkgs.espanso-wayland` when Wayland support is on.
- It creates a wrapper script that checks `$WAYLAND_DISPLAY` at runtime and launches the binary for the graphical session.

The repository's Home Manager app module leaves those defaults in place, adding only its configs, matches, and service restart policy once `services.espanso.extended.enable` is true.

### Closure Size

A host that runs only one display server can disable the other's support:

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

```nix
{
  services.espanso = {
    package = pkgs.espanso;  # X11 variant
    package-wayland = pkgs.espanso-wayland;  # Wayland variant
  };
}
```
