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
  config,
  lib,
  pkgs,
  ...
}:
let
  NemoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nemo.extended;
    in
    {
      options.programs.nemo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable nemo.";
        };

        package = lib.mkPackageOption pkgs "nemo" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nemo = NemoModule;
}
