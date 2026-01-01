/*
  Package: inkscape
  Description: Vector graphics editor.
  Homepage: https://www.inkscape.org
  Documentation: https://inkscape.org/doc/
  Repository: https://gitlab.com/inkscape/inkscape

  Summary:
    * Professional-grade vector graphics editor for creating and editing SVG illustrations, icons, logos, and complex artwork.
    * Supports a wide range of formats with powerful path operations, text tools, layers, and extensible plugin system.

  Options:
    --export-filename: Export document to specified file path.
    --export-type: Set export format (svg, png, pdf, eps, ps, emf, wmf, xaml).
    --export-area-page: Export the entire page area.
    --export-dpi: Set resolution for raster exports.
    --shell: Enter interactive shell mode for batch processing commands.
*/
_:
let
  InkscapeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.inkscape.extended;
    in
    {
      options.programs.inkscape.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable inkscape.";
        };

        package = lib.mkPackageOption pkgs "inkscape" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.inkscape = InkscapeModule;
}
