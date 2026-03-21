/*
  Package: remmina
  Description: GTK remote desktop client for managing saved connection profiles.
  Homepage: https://remmina.org/
  Documentation: https://remmina.gitlab.io/remminadoc.gitlab.io/
  Repository: https://gitlab.com/Remmina/Remmina

  Summary:
    * Provides a tabbed GTK client for RDP, VNC, SPICE, NX, X2Go, SSH, SFTP, and related remote-access workflows.
    * Supports reusable connection profiles, SSH tunneling, and plugin-driven protocol integration from one interface.

  Options:
    remmina: Launch the graphical client and browse saved connection profiles.
    -c <file.remmina>: Connect using a saved profile file or a supported URI.
    --set-option key=value --update-profile <file.remmina>: Modify stored profile settings from the command line.
*/
_:
let
  RemminaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.remmina.extended;
    in
    {
      options.programs.remmina.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable remmina.";
        };

        package = lib.mkPackageOption pkgs "remmina" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.remmina = RemminaModule;
}
