/*
  Package: cosmic-term
  Description: POP!_OS COSMIC desktop terminal emulator with GPU-accelerated rendering and ligature support.
  Homepage: https://github.com/pop-os/cosmic-term
  Documentation: https://github.com/pop-os/cosmic-term#readme
  Repository: https://github.com/pop-os/cosmic-term

  Summary:
    * Builds on alacritty_terminal and cosmic-text to deliver a fluid, Wayland-friendly terminal experience with ligatures and themeable UI.
    * Integrates with COSMIC shell conventions, offering menus for profiles, color schemes, and GPU/CPU rendering fallbacks.

  Options:
    cosmic-term: Launch the terminal emulator window using the default COSMIC profile.
    View → Color schemes…: Import or switch themes directly from the UI.
    Settings → Profiles: Configure fonts, padding, and keybindings for new windows.

  Example Usage:
    * `cosmic-term` — Start the COSMIC terminal with GPU rendering when available.
    * `cosmic-term` (then press `Ctrl+Shift+P`) — Open the command palette to access settings and appearance controls.
    * `View → Color schemes…` — Import an `.itermcolors` or `.json` theme for reuse across sessions.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.cosmic-term.extended;
  CosmicTermModule = {
    options.programs.cosmic-term.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable cosmic-term.";
      };

      package = lib.mkPackageOption pkgs "cosmic-term" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.cosmic-term = CosmicTermModule;
}
