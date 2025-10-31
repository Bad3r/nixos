/*
  Package: i3status-rust
  Description: Rust-based status bar generator compatible with i3bar, swaybar, and waybar protocols.
  Homepage: https://github.com/greshake/i3status-rust
  Documentation: https://github.com/greshake/i3status-rust#readme
  Repository: https://github.com/greshake/i3status-rust

  Summary:
    * Renders highly configurable status bars via TOML configuration, supporting blocks for system metrics, media, weather, and custom scripts.
    * Output conforms to the i3bar JSON protocol and swaybar pango markup, enabling drop-in use across tiling window managers.

  Options:
    -c <config>: Use a specific TOML configuration file (default: `~/.config/i3status-rust/config.toml`).
    -w <config-dir>: Watch the configuration directory for changes and reload live.
    --stdout: Print bar output to stdout (useful for debugging or piping).
    --version: Display the program version.

  Example Usage:
    * `i3status-rs -c ~/.config/i3status-rust/config.toml` — Run with a custom configuration.
    * `i3status-rs --stdout` — Inspect generated JSON output for troubleshooting.
    * `i3status-rs -w ~/.config/i3status-rust/` — Enable live reloading when editing configuration files.
*/
_:
let
  I3statusRustModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."i3status-rust".extended;
    in
    {
      options.programs.i3status-rust.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable i3status-rust.";
        };

        package = lib.mkPackageOption pkgs "i3status-rust" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.i3status-rust = I3statusRustModule;
}
