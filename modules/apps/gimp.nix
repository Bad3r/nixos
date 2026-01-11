/*
  Package: gimp
  Description: GNU Image Manipulation Program.
  Homepage: https://www.gimp.org/
  Documentation: https://docs.gimp.org/
  Repository: https://github.com/GNOME/gimp

  Summary:
    * Raster graphics editor for photo retouching, image composition, and image authoring.
    * Extensible platform with support for plugins, scripts, and advanced selection tools.
*/
_:
let
  GimpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gimp.extended;
    in
    {
      options.programs.gimp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gimp.";
        };

        package = lib.mkPackageOption pkgs "gimp" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gimp = GimpModule;
}
