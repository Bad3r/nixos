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
    mc alias set <name> <url> <access> <secret>: Configure a storage endpoint alias.
    mc cp <src> <dest>: Copy objects or directories between buckets and local paths.
    mc mirror --watch <src> <dest>: Continuously synchronize directories to object storage.
*/

{
  flake.nixosModules.apps."minio-client" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."minio-client" ];
    };
}
