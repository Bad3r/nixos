/*
  Package: espanso
  Description: Cross-platform text expander written in Rust.
  Homepage: https://espanso.org
  Documentation: https://espanso.org/docs/
  Repository: https://github.com/espanso/espanso

  Summary:
    * Detects when you type a keyword (trigger) and replaces it with predefined text (expansion) while typing.
    * Supports variables (date, shell, clipboard), forms, regex triggers, and app-specific configurations.
    * Configures the X11-native build to keep the setup lean on System76 desktops.

  Configuration:
    * Uses Home Manager's services.espanso module with declarative configs and matches.
    * Configs: general espanso settings (notifications, backend, app filters).
    * Matches: trigger definitions with variables and expansions.
    * Auto-generates YAML files to ~/.config/espanso/.

  Display Server Support:
    * Ships only the X11 build by default; enable Wayland manually if you need it.

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
    {
      home.packages = [ pkgs.espanso ];

      services.espanso = {
        enable = lib.mkForce true;
        x11Support = lib.mkDefault true;
        waylandSupport = lib.mkDefault false;

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
