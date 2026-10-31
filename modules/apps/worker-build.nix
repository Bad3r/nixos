/*
  Package: worker-build
  Description: Build tool for workers-rs projects that compiles Rust to Workers-ready WebAssembly bundles.
  Homepage: https://github.com/cloudflare/workers-rs/tree/main/worker-build
  Documentation: https://github.com/cloudflare/workers-rs/tree/main/worker-build#readme
  Repository: https://github.com/cloudflare/workers-rs

  Summary:
    * Produces the `worker/` output directory consumed by Cloudflare Workers deployments.

  Options:
    worker-build --release: Forward build flags to `wasm-pack` for optimized release artifacts.
*/
_:
let
  WorkerBuildModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."worker-build".extended;
    in
    {
      options.programs.worker-build.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable worker-build.";
        };

        package = lib.mkPackageOption pkgs "worker-build" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.worker-build = WorkerBuildModule;
}
