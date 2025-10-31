/*
  Package: pixman
  Description: Low-level pixel manipulation library used by cairo and other renderers.
  Homepage: https://cairographics.org/
  Repository: https://gitlab.freedesktop.org/pixman/pixman

  Summary:
    * Supplies compositing and raster operations for 2D graphics stacks.
    * Provides the `pixman-1.pc` pkg-config file that native builds like node-canvas require.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pixman.extended;
  PixmanModule = {
    options.programs.pixman.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable pixman.";
      };

      package = lib.mkPackageOption pkgs "pixman" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.pixman = PixmanModule;
}
