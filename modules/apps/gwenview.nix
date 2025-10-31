/*
  Package: gwenview
  Description: KDE’s fast image viewer with basic editing and slideshow capabilities.
  Homepage: https://apps.kde.org/gwenview/
  Documentation: https://docs.kde.org/stable5/en/gwenview/gwenview/
  Repository: https://invent.kde.org/graphics/gwenview

  Summary:
    * Offers a lightweight viewer with thumbnail browsing, fullscreen slideshows, and support for RAW formats via KImageFormats plugins.
    * Provides basic editing (crop, rotate, resize), tagging, and integration with KDE Services for sharing and printing.

  Options:
    gwenview <files>: Open one or more images directly.
    --fullscreen: Start Gwenview in fullscreen slideshow mode.
    --slideshow: Launch fullscreen slideshow immediately.
    --hide-menubar: Run without the menubar visible.

  Example Usage:
    * `gwenview photos/*.jpg` — Browse a folder of images with thumbnails and metadata.
    * `gwenview --fullscreen vacation/` — Start a fullscreen slideshow for a directory.
    * `gwenview --slideshow --interval 5 gallery/` — Run an auto-advancing slideshow with a five-second interval.
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
      cfg = config.programs.gwenview.extended;
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
