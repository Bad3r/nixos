/*
  Package: rar
  Description: Proprietary RAR command-line archiver from RARLAB for creating and extracting RAR archives.
  Homepage: https://www.rarlab.com/
  Documentation: https://www.win-rar.com/help/winrar/en/html/index.htm
  Repository: https://www.rarlab.com/download.htm

  Summary:
    * Creates, updates, and repairs multi-volume RAR archives with recovery records and strong AES-256 encryption support.
    * Provides cross-platform command-line tools (`rar`, `unrar`) compatible with Windows and Unix workflows.

  Options:
    a ARCHIVE FILES: Add files or directories to a RAR archive, creating it if missing.
    x ARCHIVE: Extract archive contents with full paths, creating directories as needed.
    t ARCHIVE: Test archive integrity without extracting files.
    -m5: Apply maximum compression level (0–5) when adding files.
    -pPASSWORD: Encrypt archive entries with the supplied password (prompted if omitted).

  Example Usage:
    * `rar a backups/project.rar src/ docs/` — Create a RAR archive from project directories.
    * `rar a -m5 -p$(pass show infra/rar-password) secure.rar secrets/` — Compress sensitive data with maximum compression and encryption.
    * `unrar x downloads/fonts.rar` — Extract archive contents preserving directory structure.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  RarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rar.extended;
    in
    {
      options.programs.rar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable rar.";
        };

        package = lib.mkPackageOption pkgs "rar" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rar = RarModule;
}
