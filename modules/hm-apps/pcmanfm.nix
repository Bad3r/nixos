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
    pcmanfm: Launch the graphical file manager.
    pcmanfm --desktop: Manage the desktop background and icons.
    pcmanfm --daemon-mode: Run in the background to handle mounts and desktops.
    pcmanfm --set-wallpaper=<file>: Apply a wallpaper through the LXDE desktop.
    pcmanfm --profile <name>: Use an alternate profile directory for settings.

  Example Usage:
    * `pcmanfm` — Browse local and remote files using a lightweight GTK interface.
    * `pcmanfm --desktop` — Allow PCManFM to draw desktop icons when running LXDE or Openbox.
    * `pcmanfm --set-wallpaper ~/Pictures/wall.jpg` — Change wallpaper without opening additional tools.
*/

{
  flake.homeManagerModules.apps.pcmanfm =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.pcmanfm ];
    };
}
