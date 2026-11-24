/*
  Package: freerdp
  Description: Free implementation of the Remote Desktop Protocol, with X11, Wayland, and SDL clients.
  Homepage: https://www.freerdp.com/
  Documentation: https://github.com/FreeRDP/FreeRDP/wiki
  Repository: https://github.com/FreeRDP/FreeRDP

  Summary:
    * Installs `xfreerdp`, `wlfreerdp`, and `sdl-freerdp` as RDP clients, plus the `freerdp-proxy` and `freerdp-shadow-cli` servers.
    * Ships the WinPR helpers `winpr-hash` and `winpr-makecert` for NTLM hashes and self-signed certificates.

  Options:
    /v:<host>[:port]: Connect to the RDP server.
    /u:<user> /p:<password>: Authenticate with the given credentials.
    /size:<w>x<h>: Set the desktop size, or use /f for fullscreen.
    /gfx: Enable the RDP graphics pipeline for H.264 decoding.
*/
_:
let
  FreerdpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.freerdp.extended;
    in
    {
      options.programs.freerdp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable FreeRDP.";
        };

        package = lib.mkPackageOption pkgs "freerdp" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.freerdp = FreerdpModule;
}
