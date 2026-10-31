/*
  Package: webex
  Description: All-in-one app to call, meet, message, and get work done.
  Homepage: https://webex.com/
  Documentation: https://help.webex.com/
  Repository: nil

  Summary:
    * Video meetings, voice calls, team messaging, and file sharing in one client.
    * Scheduled and instant meetings, persistent spaces, screen sharing, and recording.

  Notes:
    * x86_64 Linux only.
*/
_:
let
  WebexModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.webex.extended;
    in
    {
      options.programs.webex.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable webex.";
        };

        package = lib.mkPackageOption pkgs "webex" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "webex" ];
  flake.nixosModules.apps.webex = WebexModule;
}
