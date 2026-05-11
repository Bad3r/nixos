/*
  Package: librsvg
  Description: GNOME SVG rendering library with the `rsvg-convert` command-line renderer.
  Homepage: https://gitlab.gnome.org/GNOME/librsvg
  Documentation: https://gnome.pages.gitlab.gnome.org/librsvg/Rsvg-2.0/
  Repository: https://gitlab.gnome.org/GNOME/librsvg

  Summary:
    * Renders static SVG documents to Cairo surfaces for desktop icons, thumbnails, and application assets.
    * Provides `rsvg-convert` for converting SVG files to PNG, PDF, PostScript, EPS, or SVG output.

  Options:
    -f, --format <format>: Select the output format; defaults to `png`.
    -o, --output <filename>: Write output to a file instead of stdout.
    -w, --width <length>: Set rendered image width.
    -h, --height <length>: Set rendered image height.
    -b, --background-color <color>: Set a CSS background color instead of transparent output.
    -s, --stylesheet <filename.css>: Apply an external CSS stylesheet while rendering.
*/
_:
let
  LibrsvgModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.librsvg.extended;
    in
    {
      options.programs.librsvg.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable librsvg.";
        };

        package = lib.mkPackageOption pkgs "librsvg" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.librsvg = LibrsvgModule;
}
