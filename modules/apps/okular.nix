/*
  Package: okular
  Description: KDE universal document viewer supporting PDF, EPUB, comics, images, and more.
  Homepage: https://okular.kde.org/
  Documentation: https://docs.kde.org/stable5/en/okular/okular/
  Repository: https://invent.kde.org/graphics/okular

  Summary:
    * Offers annotation tools, form filling, text-to-speech, and presentation mode with wide format support via KIO plugins.
    * Provides review features (highlights, stamps), table of contents navigation, and advanced search with regular expressions.

  Options:
    okular <file>: Open documents from the command line.
    --presentation: Launch in fullscreen presentation mode.
    --print: Send a document directly to the printer queue.
    --unique: Ensure a single Okular instance handles all documents.

  Example Usage:
    * `okular report.pdf` — View and annotate a PDF document.
    * `okular --presentation slides.pdf` — Present a slideshow using a PDF deck.
    * `okular --print invoice.pdf` — Open the print dialog immediately for a file.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  KdePackagesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.okular.extended;
    in
    {
      options.programs.kdePackages.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable kdePackages.";
        };

        package = lib.mkPackageOption pkgs "kdePackages" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.kdePackages = KdePackagesModule;
}
