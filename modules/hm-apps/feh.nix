/*
  Package: feh
  Description: Light-weight image viewer.
  Homepage: https://feh.finalrewind.org/
  Documentation: https://feh.finalrewind.org/manual/
  Repository: https://github.com/derf/feh

  Summary:
    * Versatile image viewer for X11 with slideshow, thumbnail, and wallpaper-setting modes.
    * Supports complex multi-monitor setups, keyboard-driven navigation, and scripting via extensive command-line flags.

  Options:
    --recursive <dir>: Include images from subdirectories when browsing.
    --bg-fill <image>: Set the desktop background using feh’s wallpaper helper.
    --zoom <percent>: Adjust zoom level on startup.
    --list: Print metadata about images instead of opening the viewer.

  Example Usage:
    * `feh ~/Pictures` -- Browse photos in slideshow mode with keyboard navigation.
    * `feh --bg-fill ~/Pictures/wallpaper.jpg` -- Apply a wallpaper across monitors.
    * `feh --recursive --sort name ~/Wallpapers` -- Present a sorted slideshow across nested directories.
*/

{
  flake.homeManagerModules.apps.feh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.feh.extended;
    in
    {
      options.programs.feh.extended = {
        enable = lib.mkEnableOption "Light-weight image viewer.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.feh ];
      };
    };
}
