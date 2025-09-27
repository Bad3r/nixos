/*
  Package: s5cmd
  Description: High-performance parallel S3 and object storage command-line tool.
  Homepage: https://github.com/peak/s5cmd
  Documentation: https://github.com/peak/s5cmd#readme
  Repository: https://github.com/peak/s5cmd

  Summary:
    * Executes S3 operations such as copy, sync, and delete with aggressive parallelism for large datasets.
    * Supports wildcard expansions, command batching from files, and integration with AWS-compatible endpoints.

  Options:
    --concurrency <n>: Control the number of parallel transfer workers when moving large datasets.
    --endpoint-url <url>: Target alternative S3-compatible endpoints (MinIO, R2, etc.).
    --profile <name>: Use AWS credentials from a specific profile for authenticated operations.
*/

{
  flake.nixosModules.apps.s5cmd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.s5cmd ];
    };
}
