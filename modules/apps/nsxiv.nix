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
  flake.nixosModules.apps.nsxiv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nsxiv ];
    };
}
