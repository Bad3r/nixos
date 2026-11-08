/*
  Package: inotify-tools
  Description: Utilities for watching Linux filesystem events.
  Homepage: https://github.com/inotify-tools/inotify-tools/wiki
  Documentation: https://github.com/inotify-tools/inotify-tools/wiki
  Repository: https://github.com/inotify-tools/inotify-tools

  Summary:
    * Provides `inotifywait` for waiting on changes to files and directories.
    * Requires a running watcher; filesystem events do not wake an idle agent session.
*/
_:
let
  InotifyToolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."inotify-tools".extended;
    in
    {
      options.programs.inotify-tools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable inotify-tools.";
        };

        package = lib.mkPackageOption pkgs "inotify-tools" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.inotify-tools = InotifyToolsModule;
}
