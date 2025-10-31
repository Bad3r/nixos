/*
  Package: planify
  Description: GTK task and project manager integrating Todoist, Nextcloud Tasks, CalDAV, and more.
  Homepage: https://jhass.github.io/planify/
  Documentation: https://github.com/jhass/planify#readme
  Repository: https://github.com/jhass/planify

  Summary:
    * Provides a modern GNOME-style interface for managing tasks with support for multiple backends, recurring reminders, Kanban boards, and offline mode.
    * Includes quick capture, subtasks, attachment support, and synchronization with popular productivity services.

  Options:
    planify: Launch the GTK application.
    Settings → Accounts: Configure Todoist, CalDAV, or local account integrations.
    (CLI options are minimal; interactions occur within the GUI.)

  Example Usage:
    * `planify` — Open the desktop client to review tasks and projects.
    * Use the “Quick Add” shortcut (`Ctrl+Space`) to capture tasks rapidly.
    * Configure notifications and synchronization intervals via Preferences.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  PlanifyModule = { config, lib, pkgs, ... }:
  let
    cfg = config.programs.planify.extended;
  in
  {
    options.programs.planify.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable planify.";
      };

      package = lib.mkPackageOption pkgs "planify" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.planify = PlanifyModule;
}
