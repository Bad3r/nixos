/*
  Package: minio-client
  Description: MinIO Client (`mc`) for managing S3-compatible object storage.
  Homepage: https://min.io/
  Documentation: https://min.io/docs/minio/linux/reference/minio-mc.html
  Repository: https://github.com/minio/mc

  Summary:
    * Provides an `aws-cli`-like interface for interacting with MinIO and other S3-compatible endpoints.
    * Supports replication, lifecycle configuration, mirroring, and administrative operations for buckets.

  Options:
    --recursive: Copy or mirror directory trees recursively when used with `mc cp` or `mc mirror`.
    --watch: Keep `mc mirror --watch` running to stream incremental changes.
    --json: Emit machine-readable output for automation scripts.
*/
_:
let
  MinioClientModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."minio-client".extended;
    in
    {
      options.programs.minio-client.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable minio-client.";
        };

        package = lib.mkPackageOption pkgs "minio-client" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.minio-client = MinioClientModule;
}
