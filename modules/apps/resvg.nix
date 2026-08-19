/*
  Package: resvg
  Description: SVG rendering library.
  Homepage: https://github.com/linebender/resvg
  Documentation: https://docs.rs/resvg/latest/resvg/
  Repository: https://github.com/linebender/resvg

  Summary:
    * Renders static SVG files to PNG through Rust, C, and command-line interfaces.
    * Provides portable and reproducible rendering for SVG assets and image conversion.

  Options:
    <in-svg> <out-png>: Render an SVG file to a PNG file.
    -c: Write the output PNG to stdout.
    -w, --width <length>: Set the output width in pixels.
    -h, --height <length>: Set the output height in pixels.
    -z, --zoom <factor>: Scale the output by a zoom factor.
    --dpi <dpi>: Set the output resolution.
    --background <color>: Set a background color instead of transparent output.
    --stylesheet <path>: Inject a stylesheet while resolving CSS attributes.
*/
_:
let
  ResvgModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.resvg.extended;
    in
    {
      options.programs.resvg.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable resvg.";
        };

        package = lib.mkPackageOption pkgs "resvg" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.resvg = ResvgModule;
}
