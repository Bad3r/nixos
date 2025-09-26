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
  flake.nixosModules.apps.planify =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.planify ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.planify ];
    };
}
