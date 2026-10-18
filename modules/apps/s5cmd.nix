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
_:
let
  S5cmdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.s5cmd.extended;
    in
    {
      options.programs.s5cmd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable s5cmd.";
        };

        package = lib.mkPackageOption pkgs "s5cmd" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ];
          etc."cloudflare-r2/s5cmd.env.example".text = ''
            # Copy to a safe location and source before using s5cmd
            # export AWS_ACCESS_KEY_ID=...
            # export AWS_SECRET_ACCESS_KEY=...
            # For R2 set a custom endpoint URL (per-bucket or account level)
            # s5cmd takes endpoints as part of the URL you use, e.g.:
            #   s5cmd ls s3://<bucket>/ --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
            # Or set AWS_ENDPOINT_URL to avoid repeating:
            # export AWS_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
          '';
        };
      };
    };
in
{
  flake.nixosModules.apps.s5cmd = S5cmdModule;
}
