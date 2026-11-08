/*
  Package: tigervnc
  Description: VNC viewer and server for remote graphical sessions.
  Homepage: https://tigervnc.org/
  Documentation: https://tigervnc.org/doc/vncviewer.html
  Repository: https://github.com/TigerVNC/tigervnc

  Summary:
    * Provides `vncviewer` for viewing and interacting with a remote display.
    * Supports password authentication and SSH tunnelling.
*/
_:
let
  TigervncModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tigervnc.extended;
    in
    {
      options.programs.tigervnc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tigervnc.";
        };

        package = lib.mkPackageOption pkgs "tigervnc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tigervnc = TigervncModule;
}
