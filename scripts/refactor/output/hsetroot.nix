/*
  Package: hsetroot
  Description: Lightweight X11 wallpaper setter supporting gradients, solid colors, and image scaling.
  Homepage: https://github.com/himdel/hsetroot
  Documentation: https://github.com/himdel/hsetroot#usage
  Repository: https://github.com/himdel/hsetroot

  Summary:
    * Sets root window backgrounds using solid colors, gradients, or images with tiling, stretching, or center placement.
    * Useful in window manager setups (i3, bspwm, xmonad) where a simple, scriptable wallpaper tool is preferred.

  Options:
    -solid <color>: Fill the root window with a solid color (hex or named).
    -gradient <dir> <color1> <color2>: Create gradients with specified direction (e.g. `vert`, `horz`).
    -fill/-tile/-center/-stretch <file>: Place an image using the chosen mode.
    -blur <radius>: Apply a blur effect to the background image.
    -brightness <value>: Adjust brightness of the resulting background.

  Example Usage:
    * `hsetroot -solid '#1d2021'` — Set a solid background color.
    * `hsetroot -gradient vert '#1d2021' '#282c34'` — Apply a vertical gradient between two colors.
    * `hsetroot -fill ~/Pictures/wallpaper.jpg` — Fill the screen with an image preserving aspect ratio.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hsetroot.extended;
  HsetrootModule = {
    options.programs.hsetroot.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable hsetroot.";
      };

      package = lib.mkPackageOption pkgs "hsetroot" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.hsetroot = HsetrootModule;
}
