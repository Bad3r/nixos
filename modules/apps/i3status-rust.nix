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
    --never-pause: Ignore i3's requests to pause the bar while hidden or fullscreen.
    -j, --threads <n>: Set the maximum number of blocking threads (default: 2).
    --version: Display the program version.
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
          description = "Whether to enable i3status-rust.";
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
