/*
  Package: nemo
  Description: Cinnamon’s file manager with dual-pane browsing, tabs, and integration with GNOME virtual file systems.
  Homepage: https://github.com/linuxmint/nemo
  Documentation: https://github.com/linuxmint/nemo#readme
  Repository: https://github.com/linuxmint/nemo

  Summary:
    * Provides a feature-rich file manager supporting SMB/NFS/GVFS mounts, context-menu extensions, bulk rename, and media previews.
    * Integrates Cinnamon desktop conventions while remaining usable in other desktop environments with underlying GNOME services.

  Options:
    nemo <path>: Open Nemo at a specified directory.
    nemo --quit: Close existing Nemo instances.
    nemo --new-window: Force opening a new window even if one is already running.
    nemo --no-desktop: Launch without managing desktop icons (useful outside Cinnamon).

  Example Usage:
    * `nemo ~/Projects` — Browse the Projects directory in a new Nemo window.
    * `nemo --new-window smb://server/share` — Connect to a remote SMB share.
    * `nemo --no-desktop` — Use Nemo purely as a file manager in non-Cinnamon environments.
*/

{
  flake.nixosModules.apps.nemo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nemo ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nemo ];
    };
}
