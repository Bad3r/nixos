/*
  Package: vtracer
  Description: Raster to vector graphics converter.
  Homepage: https://github.com/visioncortex/vtracer
  Documentation: https://www.visioncortex.org/vtracer-docs/
  Repository: https://github.com/visioncortex/vtracer

  Summary:
    * Converts raster images such as PNG and JPEG files into SVG vector graphics.
    * Traces colored artwork, scans, photographs, blueprints, and pixel art with configurable clustering and curve
      fitting.

  Options:
    <input> <output>: Convert a raster input image to an SVG output file.
    -i, --input <input>: Specify the input raster image.
    -o, --output <output>: Specify the output SVG file.
    --preset <preset>: Start from a black-and-white, poster, or photo preset.
    --clustering <clustering>: Select the region-forming algorithm.
    --hierarchical <hierarchical>: Select stacked output or a seam-free cutout mosaic.
    -m, --mode <mode>: Select pixel, polygon, or spline curve fitting.
    --palette <palette>: Constrain output colors to a comma-separated hex palette.
    --simplify <tolerance>: Simplify curves within the specified pixel tolerance.
*/
_:
let
  VtracerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vtracer.extended;
    in
    {
      options.programs.vtracer.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vtracer.";
        };

        package = lib.mkPackageOption pkgs "vtracer" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.vtracer = VtracerModule;
}
