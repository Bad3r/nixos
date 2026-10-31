/*
  Package: dropbox
  Description: Official Dropbox desktop client for cloud file synchronization.
  Homepage: https://www.dropbox.com/
  Documentation: https://help.dropbox.com/
  Repository: nil

  Summary:
    * Syncs files between local folders and Dropbox cloud storage with selective sync and Smart Sync.
    * Provides file versioning, sharing links, LAN sync optimizations, and collaboration features.

  Options:
    dropbox start: Launch the daemon and begin syncing.
    dropbox stop: Stop the background daemon.
    dropbox filestatus <path>: Inspect sync status for a specific file or directory.
*/
_:
let
  DropboxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dropbox.extended;
    in
    {
      options.programs.dropbox.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dropbox.";
        };

        package = lib.mkPackageOption pkgs "dropbox" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  # nixpkgs' dropbox FHS env includes firefox-bin.
  nixpkgs.allowedUnfreePackages = [
    "dropbox"
    "firefox-bin"
    "firefox-bin-unwrapped"
  ];
  flake.nixosModules.apps.dropbox = DropboxModule;
}
