/*
  Package: espanso
  Description: Cross-platform text expander written in Rust.
  Homepage: https://espanso.org
  Documentation: https://espanso.org/docs/
  Repository: https://github.com/espanso/espanso

  Summary:
    * Detects when you type a keyword (trigger) and replaces it with predefined text (expansion) while typing.
    * Supports variables (date, shell, clipboard), forms, regex triggers, and app-specific configurations.
    * Works on X11 and Wayland (auto-detection based on $WAYLAND_DISPLAY).

  Configuration:
    * Uses Home Manager's services.espanso module with declarative configs and matches.
    * Configs: general espanso settings (notifications, backend, app filters).
    * Matches: trigger definitions with variables and expansions.
    * Auto-generates YAML files to ~/.config/espanso/.

  Display Server Support:
    * Both X11 and Wayland support enabled by default on Linux.
    * Module sets x11Support=true, waylandSupport=true, and package-wayland=pkgs.espanso-wayland.
    * Home Manager creates a wrapper that checks $WAYLAND_DISPLAY and launches the correct binary.
    * To reduce closure size, disable unused support:
      services.espanso.x11Support = false;  # Wayland-only
      services.espanso.waylandSupport = false;  # X11-only

  Example Usage:
    * Default setup provides common date/time variables and basic expansions.
    * Add custom matches via services.espanso.matches attribute set.
    * Create app-specific configs via services.espanso.configs.

  Common Patterns:
    * Date/time: ":now" → "2025-10-08 14:30"
    * Email: ":email" → "user@example.com"
    * Code snippets: ":shebang" → "#!/usr/bin/env bash"
    * Forms: interactive prompts for dynamic content
    * Regex: pattern-based replacements with capture groups
*/

{
  flake.homeManagerModules.apps.espanso =
    { lib, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux;
    in
    {
      services.espanso = {
        enable = true;

        # Enable both X11 and Wayland support on Linux for auto-detection
        x11Support = lib.mkDefault isLinux;
        waylandSupport = lib.mkDefault isLinux;

        # Ensure Wayland package is available when waylandSupport is enabled
        "package-wayland" = lib.mkDefault (if isLinux then pkgs.espanso-wayland else null);

        # Default configuration
        configs = {
          default = {
            show_notifications = false;
            # Uncomment for clipboard backend (better compatibility with some apps)
            # backend = "Clipboard";
          };
        };

        # Default matches with common patterns
        matches = {
          # Base expansions with date/time variables
          base = {
            matches = [
              {
                trigger = ":test";
                replace = "test 1.2.3";
              }
              {
                trigger = ":date";
                replace = "{{currentdate}}";
              }
              {
                trigger = ":time";
                replace = "{{currenttime}}";
              }
              {
                trigger = ":now";
                replace = "{{currentdate}} {{currenttime}}";
              }
              {
                trigger = ":isodate";
                replace = "{{isodate}}";
              }
            ];

            global_vars = [
              {
                name = "currentdate";
                type = "date";
                params = {
                  format = "%Y-%m-%d";
                };
              }
              {
                name = "currenttime";
                type = "date";
                params = {
                  format = "%H:%M";
                };
              }
              {
                name = "isodate";
                type = "date";
                params = {
                  format = "%Y-%m-%dT%H:%M:%S%z";
                };
              }
            ];
          };

          # Development/coding snippets
          dev = {
            matches = [
              {
                trigger = ":shebang";
                replace = "#!/usr/bin/env bash";
              }
              {
                trigger = ":shebangnix";
                replace = "#!/usr/bin/env nix-shell\n#!nix-shell -i bash";
              }
              {
                trigger = ":todo";
                replace = "# TODO: ";
              }
              {
                trigger = ":fixme";
                replace = "# FIXME: ";
              }
            ];
          };
        };
      };
    };
}
