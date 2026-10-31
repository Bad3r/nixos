/*
  Package: poppler-utils
  Description: Poppler command-line utilities for inspecting, extracting, and rendering PDF content.
  Homepage: https://poppler.freedesktop.org/
  Documentation: https://poppler.freedesktop.org/
  Repository: https://gitlab.freedesktop.org/poppler/poppler

  Summary:
    * Bundles utilities such as `pdfinfo`, `pdftotext`, `pdftoppm`, and `pdfimages` for common PDF parsing and conversion workflows.
    * Supports metadata inspection, text extraction, rasterization, and embedded asset recovery from shell pipelines.

  Options:
    pdfinfo: Print document metadata, page geometry, encryption state, and box information.
    pdftotext: Extract page text into plain text or layout-preserving output.
    pdftoppm: Rasterize PDF pages to PPM, PNG, JPEG, or TIFF images.
    pdfimages: Extract embedded bitmap images without re-rendering pages.
*/
_:
let
  PopplerUtilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."poppler-utils".extended;
    in
    {
      options.programs.poppler-utils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable poppler-utils.";
        };

        package = lib.mkPackageOption pkgs "poppler-utils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.poppler-utils = PopplerUtilsModule;
}
