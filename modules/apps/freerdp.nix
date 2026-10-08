/*
  Package: freerdp
  Description: Free implementation of the Remote Desktop Protocol, providing the xfreerdp client.
  Homepage: https://www.freerdp.com/
  Documentation: https://github.com/FreeRDP/FreeRDP/wiki/CommandLineInterface
  Repository: https://github.com/FreeRDP/FreeRDP

  Summary:
    * Installs the FreeRDP 3 client so RemoteApp diagnostics and the certificate prompt run in a terminal with visible output.
    * Provides the same xfreerdp binary the WinApps launcher wraps, so a diagnostic session and a launcher session behave alike.

  Options:
    xfreerdp /v:<address> /u:<user>: Open a desktop session; FreeRDP asks for the password and for an unknown certificate on the terminal.
    /app:program:<path>: Start one RemoteApp program instead of the desktop.
    /drive:<name>,<path>: Share one host directory with the session as \\tsclient\<name>.
    /wm-class:<class>: Set the X11 window class of RemoteApp windows.

  Example Usage:
    * `xfreerdp /u:alice /v:<address>` -- Connect to a guest desktop and answer the certificate prompt.
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
          description = "Whether to enable freerdp.";
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
