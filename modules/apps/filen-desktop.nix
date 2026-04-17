/*
  Package: filen-desktop
  Description: Filen Desktop Client.
  Homepage: https://filen.io/products/desktop
  Documentation: https://docs.filen.io/docs/desktop/
  Repository: https://github.com/FilenCloudDienste/filen-desktop

  Summary:
    * Synchronizes local folders with Filen end-to-end encrypted cloud storage through the desktop client.
    * Mounts network drives and exposes local WebDAV or S3 endpoints alongside native file management.

  Options:
    permanent synchronizations: Configure ongoing one-way, two-way, or backup-style folder sync relationships.
    network drive: Mount Filen storage as a local drive with native desktop file access.
    local WebDAV server: Serve account contents to other local apps or devices through WebDAV.
    local S3 server: Expose account contents through a local S3-compatible endpoint.
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
