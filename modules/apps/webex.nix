/*
  Package: webex
  Description: All-in-one app to call, meet, message, and get work done.
  Homepage: https://webex.com/
  Documentation: https://help.webex.com/
  Repository: nil

  Summary:
    * Unified workspace combining HD video meetings, voice calls, team messaging, and file sharing.
    * Supports scheduled and instant meetings, persistent spaces, screen sharing, virtual backgrounds, and recording.

  Options:
    webex: Launches the Cisco Webex desktop client (symlink to CiscoCollabHost).
    webex.desktop: Application menu entry registered under share/applications.

  Notes:
    * Proprietary Cisco binary distribution; the unfree license is registered via nixpkgs.allowedUnfreePackages.
    * Upstream ships only a Linux x86_64 build sourced from binaries.webex.com.
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
