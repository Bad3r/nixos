/*
  Package: pcmanfm
  Description: File manager with GTK interface.
  Homepage: https://blog.lxde.org/category/pcmanfm/
  Documentation: https://wiki.lxde.org/en/PCManFM
  Repository: https://github.com/lxde/pcmanfm

  Summary:
    * Lightweight file manager from the LXDE project with tabbed browsing, volume management, and desktop integration.
    * Supports custom actions, bookmarking, remote filesystems via GVfs, and drag-and-drop between panels.

  Options:
    --desktop: Manage the desktop background and icons when running under LXDE or Openbox.
    --daemon-mode: Keep pcmanfm running in the background to handle automounts and desktop management.
    --set-wallpaper=<file>: Apply a wallpaper through pcmanfm’s desktop integration.
    --profile <name>: Use an alternate profile directory for settings and bookmarks.

  Example Usage:
    * `pcmanfm` — Browse local and remote files using a lightweight GTK interface.
    * `pcmanfm --desktop` — Allow PCManFM to draw desktop icons when running LXDE or Openbox.
    * `pcmanfm --set-wallpaper ~/Pictures/wall.jpg` — Change wallpaper without opening additional tools.
*/

{
  flake.homeManagerModules.apps.pcmanfm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pcmanfm.extended;
    in
    {
      options.programs.pcmanfm.extended = {
        enable = lib.mkEnableOption "File manager with GTK interface.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.pcmanfm ];
      };
    };
}
