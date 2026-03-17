/*
  Package: mupdf
  Description: Lightweight PDF, XPS, and e-book viewer and toolkit written in portable C.
  Homepage: https://mupdf.com/
  Documentation: https://mupdf.com/docs
  Repository: https://github.com/ArtifexSoftware/mupdf

  Summary:
    * Ships the MuPDF viewer plus `mutool` commands for inspecting, cleaning, extracting, and rendering PDF content.
    * Handles PDF repair, page rasterization, object extraction, and metadata inspection without requiring a GUI workflow.

  Example Usage:
    * `mupdf report.pdf` -- Open a PDF in the lightweight MuPDF viewer.
    * `mutool info report.pdf` -- Print page, font, and object information for a PDF.
    * `mutool draw -o page-%03d.png report.pdf 1-3` -- Render the first three pages to PNG files.

  Options:
    mutool clean: Rewrite and sanitize a PDF, optionally compressing or linearizing objects.
    mutool draw: Render pages to raster formats such as PNG or PNM.
    mutool extract: Pull embedded fonts, images, and other objects from a document.
    mutool info: Inspect trailer, page, font, image, and object metadata.
*/
_:
let
  MuPdfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mupdf.extended;
    in
    {
      options.programs.mupdf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mupdf.";
        };

        package = lib.mkPackageOption pkgs "mupdf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mupdf = MuPdfModule;
}
