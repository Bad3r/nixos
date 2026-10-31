/*
  Package: unrar
  Description: Proprietary command-line utility for extracting RAR archives.
  Homepage: https://www.rarlab.com/
  Documentation: https://www.rarlab.com/rar_add.htm
  Repository: nil

  Summary:
    * Decompresses RAR and RAR5 archives, including multi-volume sets and encrypted archives (with password).
    * Supports testing archives, printing file lists, and extracting specific paths while preserving permissions.

  Options:
    unrar x archive.rar [dest]: Extract with full paths to destination directory.
    unrar e archive.rar: Extract files without recreating directory structure.
    unrar t archive.rar: Test archive integrity without extracting.
    unrar l archive.rar: List archive contents.
    -p<password>: Supply password for encrypted archives.
*/
_:
let
  UnrarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.unrar.extended;
    in
    {
      options.programs.unrar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable unrar.";
        };

        package = lib.mkPackageOption pkgs "unrar" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "unrar" ];

  flake.nixosModules.apps.unrar = UnrarModule;
}
