/*
  Package: filen-cli
  Description: CLI tool for interacting with the Filen cloud.
  Homepage: https://filen.io/products/cli
  Documentation: https://docs.filen.io/docs/cli/
  Repository: https://github.com/FilenCloudDienste/filen-cli

  Summary:
    * Accesses Filen Drive from stateless or interactive terminal sessions with end-to-end encryption.
    * Syncs folders, mounts network drives, and serves local WebDAV or S3 mirrors for automation workflows.

  Options:
    sync: Synchronize local paths with Filen cloud storage using the documented sync workflow.
    mount: Expose Filen storage as a local network drive for native file access.
    webdav: Run a local WebDAV mirror server backed by your encrypted Filen account.
    s3: Run a local S3-compatible mirror server for tools that expect S3 semantics.
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
