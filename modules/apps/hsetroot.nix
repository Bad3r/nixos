/*
  Package: hsetroot
  Description: Lightweight X11 wallpaper setter supporting gradients, solid colors, and image scaling.
  Homepage: https://github.com/himdel/hsetroot
  Documentation: https://github.com/himdel/hsetroot#usage
  Repository: https://github.com/himdel/hsetroot

  Summary:
    * Sets root window backgrounds using solid colors, gradients, or images with tiling, stretching, or center placement.

  Options:
    -solid <color>: Fill the root window with a solid color (hex or named).
    -add <color>: Add a color to the gradient range.
    -gradient <angle>: Render the gradient range at the given angle.
    -fill/-tile/-center/-cover <image>: Place an image using the chosen mode.
    -blur <radius>: Apply a blur effect to the background image.
    -brightness <value>: Adjust brightness of the resulting background.
*/
_:
let
  HsetrootModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hsetroot.extended;
    in
    {
      options.programs.hsetroot.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hsetroot.";
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
