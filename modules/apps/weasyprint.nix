/*
  Package: weasyprint
  Description: Converts HTML and CSS into PDF documents.
  Homepage: https://weasyprint.org/
  Documentation: https://doc.courtbouillon.org/weasyprint/stable/
  Repository: https://github.com/Kozea/WeasyPrint

  Summary:
    * Renders HTML and CSS, including CSS Paged Media features (`@page` rules, margin boxes, page breaks), into PDF documents.
    * Implements its own layout and text-shaping engine on top of Pango and HarfBuzz rather than wrapping a browser, so JavaScript-driven content is not executed.

  Options:
    -s: Add a user CSS stylesheet (URL or filename); repeatable.
    -e: Force the input character encoding.
    -m: Set the media type used for @media queries (defaults to print).
    -u: Set the base URL used to resolve relative resource paths.
    --pdf-variant: Generate a specific PDF/A, PDF/UA, or PDF/X compliance variant.
    -j: Set JPEG quality for embedded images, 0 (worst) to 95 (best).
    -i: Print system information and exit.
*/
_:
let
  WeasyprintModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.weasyprint.extended;
    in
    {
      options.programs.weasyprint.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable weasyprint.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "weasyprint" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.weasyprint = WeasyprintModule;
}
