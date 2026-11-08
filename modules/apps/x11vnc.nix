/*
  Package: x11vnc
  Description: VNC server for sharing an existing X11 display.
  Homepage: https://github.com/LibVNC/x11vnc
  Documentation: https://github.com/LibVNC/x11vnc/blob/master/doc/OPTIONS.md
  Repository: https://github.com/LibVNC/x11vnc

  Summary:
    * Shares an existing X server, including an Xvfb display, with VNC clients.
    * Forwards keyboard and pointer input to the shared display.
*/
_:
let
  X11vncModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.x11vnc.extended;
    in
    {
      options.programs.x11vnc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable x11vnc.";
        };

        package = lib.mkPackageOption pkgs "x11vnc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.x11vnc = X11vncModule;
}
