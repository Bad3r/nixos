/*
  Package: filen-desktop
  Description: Filen Desktop Client.
  Homepage: https://filen.io/products/desktop
  Documentation: https://docs.filen.io/docs/desktop/
  Repository: https://github.com/FilenCloudDienste/filen-desktop

  Summary:
    * Syncs local folders with Filen end-to-end encrypted cloud storage.
    * Mounts Filen as a network drive and serves it over local WebDAV or S3.
*/
_:
let
  FilenDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."filen-desktop".extended;
    in
    {
      options.programs.filen-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable filen-desktop.";
        };

        package = lib.mkPackageOption pkgs "filen-desktop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.filen-desktop = FilenDesktopModule;
}
