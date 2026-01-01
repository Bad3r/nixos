/*
  Package: potrace
  Description: Tool for tracing bitmaps into smooth, scalable vector graphics.
  Homepage: https://potrace.sourceforge.net/
  Documentation: https://potrace.sourceforge.net/potrace.1.html

  Summary:
    * Transforms bitmap images (PBM, PGM, PPM, BMP) into vector formats (EPS, PostScript, PDF, SVG, DXF).
    * Provides high-quality polygon-based tracing with configurable accuracy, smoothing, and optimization options.

  Options:
    -s: Output SVG format.
    -e: Output EPS format.
    -p: Output PostScript format.
    -b: Select backend (svg, eps, pdf, pdfpage, postscript, ps, dxf, geojson, pgm, gimppath, xfig).
    -t: Set threshold for converting greymap to bitmap (0.0 to 1.0).
    -a: Set corner threshold for smoothing (0 = no corners, 1.334 = default).
    -O: Set optimization tolerance for curve fitting.
*/
_:
let
  PotraceModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.potrace.extended;
    in
    {
      options.programs.potrace.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable potrace.";
        };

        package = lib.mkPackageOption pkgs "potrace" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.potrace = PotraceModule;
}
