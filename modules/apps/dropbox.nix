/*
  Package: dropbox
  Description: Official Dropbox desktop client for cloud file synchronization.
  Homepage: https://www.dropbox.com/
  Documentation: https://help.dropbox.com/
  Repository: https://github.com/dropbox/dropbox-api-spec

  Summary:
    * Syncs files between local folders and Dropbox cloud storage with selective sync and Smart Sync.
    * Provides file versioning, sharing links, LAN sync optimizations, and collaboration features.

  Options:
    dropbox start: Launch the daemon and begin syncing.
    dropbox stop: Stop the background daemon.
    dropbox filestatus <path>: Inspect sync status for a specific file or directory.

  Example Usage:
    * `dropbox start -i` — Run the initial setup wizard to link your account.
    * `dropbox status` — Check current synchronization state and recent activity.
    * `dropbox exclude add temp/` — Skip syncing temporary directories to the cloud.
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
          description = lib.mdDoc "Whether to enable dropbox.";
        };

        package = lib.mkPackageOption pkgs "dropbox" { };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "dropbox" ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dropbox = DropboxModule;
}
