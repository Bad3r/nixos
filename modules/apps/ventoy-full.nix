/*
  Package: ventoy-full
  Description: CLI bundle for creating multi-boot USB drives with Ventoy (no GUI).
  Homepage: https://www.ventoy.net/
  Documentation: https://www.ventoy.net/en/doc_start.html
  Repository: https://github.com/ventoy/Ventoy

  Summary:
    * Installs the full Ventoy command-line toolchain with filesystem helpers (ext4, NTFS, XFS, LUKS).
    * Lets you initialise or update Ventoy on removable media without needing the upstream GTK/Qt frontends.

  Example Usage:
    * `sudo ventoy` - Launch the interactive CLI menu to select a target disk and install Ventoy.
    * `sudo ventoy -I /dev/sdX` - Install Ventoy to `/dev/sdX` in one shot.
    * `sudo ventoy -U /dev/sdX` - Update an existing Ventoy installation.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  VentoyFullModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ventoy-full".extended;
    in
    {
      options.programs.ventoy-full.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable ventoy-full.";
        };

        package = lib.mkPackageOption pkgs "ventoy-full" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ventoy-full = VentoyFullModule;
}
