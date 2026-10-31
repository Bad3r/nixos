/*
  Package: ventoy-full
  Description: CLI bundle for creating multi-boot USB drives with Ventoy (no GUI).
  Homepage: https://www.ventoy.net/
  Documentation: https://www.ventoy.net/en/doc_start.html
  Repository: https://github.com/ventoy/Ventoy

  Summary:
    * Ships the full Ventoy command-line toolchain with filesystem helpers (ext4, NTFS, XFS, LUKS).
    * Initialises or updates Ventoy on removable media without the upstream GTK/Qt frontends.
*/
_:
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
          description = "Whether to enable ventoy-full.";
        };

        package = lib.mkPackageOption pkgs "ventoy-full" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "ventoy" ];

  flake.nixosModules.apps.ventoy-full = VentoyFullModule;
}
