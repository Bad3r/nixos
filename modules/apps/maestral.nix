/*
  Package: maestral
  Description: Open-source Dropbox client for macOS and Linux.
  Homepage: https://maestral.app
  Documentation: https://maestral.readthedocs.io
  Repository: https://github.com/samschott/maestral

  Summary:
    * Lightweight CLI client with selective sync, .mignore patterns, and multi-account support.
    * Bypasses Dropbox's three-device limit while providing file versioning and shared link management.

  Options:
    start: Initiate account linking and begin syncing.
    stop: Stop the sync daemon.
    status: Display account info, storage usage, and sync state.
    pause/resume: Temporarily suspend or continue syncing.
    excluded: View and manage excluded folders for selective sync.
    activity: Live view of items being synced.
    history: Show sync history.
    revs: List old file revisions.
    restore: Restore a previous version of a file.
    autostart: Configure automatic daemon startup on login.

  Notes:
    * Requires initial account linking via `maestral start` or the GUI.
    * Supports gitignore-style .mignore files for local exclusion patterns.
    * Can run as a systemd user service; see maestral-gui for Qt frontend.
*/
_:
let
  MaestralModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.maestral.extended;
    in
    {
      options.programs.maestral.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable maestral.";
        };

        package = lib.mkPackageOption pkgs "maestral" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.maestral = MaestralModule;
}
