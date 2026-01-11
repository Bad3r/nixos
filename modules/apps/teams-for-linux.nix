/*
  Package: teams-for-linux
  Description: Unofficial Microsoft Teams client for Linux with native system integration.
  Homepage: https://github.com/IsmaelMartinez/teams-for-linux
  Documentation: https://github.com/IsmaelMartinez/teams-for-linux/wiki
  Repository: https://github.com/IsmaelMartinez/teams-for-linux

  Summary:
    * Unofficial Teams client providing native desktop notifications and system tray integration.
    * Supports screen sharing, video calls, and all core Teams functionality through web wrapper.

  Options:
    --disable-gpu: Disable GPU acceleration if experiencing graphical issues.
    --enable-wayland: Enable native Wayland support for better performance on Wayland compositors.
*/
_:
let
  TeamsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.teams-for-linux.extended;
    in
    {
      options.programs.teams-for-linux.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable teams-for-linux.";
        };

        package = lib.mkPackageOption pkgs "teams-for-linux" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.teams-for-linux = TeamsModule;
}
