/*
  Package: filen-cli
  Description: Filen cloud storage command-line client for encrypted uploads and downloads.
  Homepage: https://filen.io/
  Documentation: https://docs.filen.io/
  Repository: https://github.com/FilenCloudDienste/filen-cli

  Summary:
    * Provides CLI automation for Filen accounts with end-to-end encrypted file storage.
    * Supports directory sync, share management, and token-based authentication for scripts.

  Options:
    filen-cli login: Authenticate with your Filen credentials and persist tokens securely.
    filen-cli sync <path> <remote>: Set up continuous sync between local folders and cloud directories.
    filen-cli share create <path>: Generate share links for collaborators with configurable permissions.

  Example Usage:
    * `filen-cli login` -- Sign in and save credentials for subsequent commands.
    * `filen-cli upload ./reports /Work/Reports` -- Upload files into an encrypted cloud folder.
    * `filen-cli sync ./Archive /Backups/Archive --watch` -- Continuously mirror a directory to Filen storage.
*/
_:
let
  FilenCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."filen-cli".extended;
    in
    {
      options.programs.filen-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable filen-cli.";
        };

        package = lib.mkPackageOption pkgs "filen-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.filen-cli = FilenCliModule;
}
