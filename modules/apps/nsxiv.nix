/*
  Package: nsxiv
  Description: Minimal X Image Viewer derived from sxiv, with focus on keyboard-driven workflows.
  Homepage: https://nsxiv.codeberg.page/
  Documentation: https://nsxiv.codeberg.page/usage.html
  Repository: https://codeberg.org/nsxiv/nsxiv

  Summary:
    * Lightweight image viewer for X11 with thumbnail grids, zoom controls, and configurable key bindings.
    * Supports animated images, basic slideshow mode, and external image manipulation via key-handler scripts.

  Options:
    nsxiv <file|dir>: Open a file or directory of images.
    nsxiv -t <dir>: Launch thumbnail mode for quick navigation.
    nsxiv -a <dir>: Start an automatic slideshow cycling through the directory.

  Example Usage:
    * `nsxiv photos/` — Browse a directory of photos with thumbnail previews.
    * `nsxiv -a wallpapers/` — Run a fullscreen slideshow cycling forever.
    * `nsxiv -eh` — Print key-handler usage details for integrating automation scripts.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  NsxivModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nsxiv.extended;
    in
    {
      options.programs.nsxiv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable nsxiv.";
        };

        package = lib.mkPackageOption pkgs "nsxiv" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nsxiv = NsxivModule;
}
