/*
  Package: planify
  Description: GTK task and project manager integrating Todoist, Nextcloud Tasks, CalDAV, and more.
  Homepage: https://jhass.github.io/planify/
  Documentation: https://github.com/jhass/planify#readme
  Repository: https://github.com/alainm23/planify

  Summary:
    * Provides a modern GNOME-style interface for managing tasks with support for multiple backends, recurring reminders, Kanban boards, and offline mode.
    * Includes quick capture, subtasks, attachment support, and synchronization with popular productivity services.
*/
_:
let
  PlanifyModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.planify.extended;
    in
    {
      options.programs.planify.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable planify.";
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
