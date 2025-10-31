/*
  Package: worker-build
  Description: Build tool for workers-rs projects that compiles Rust to Workers-ready WebAssembly bundles.
  Homepage: https://github.com/cloudflare/workers-rs/tree/main/worker-build
  Documentation: https://github.com/cloudflare/workers-rs/tree/main/worker-build#readme
  Repository: https://github.com/cloudflare/workers-rs

  Summary:
    * Wraps `wasm-pack` and esbuild to produce the `worker/` output directory consumed by Cloudflare Workers deployments.
    * Supports optional features like custom shims, wasm coredump generation, and snippet bundling for workers-rs crates.

  Options:
    worker-build --release: Forward build flags to `wasm-pack` for optimized release artifacts.
    COREDUMP=1 worker-build: Embed wasm coredump support during the build process.
    CUSTOM_SHIM=path/to/shim.js worker-build: Replace the default JavaScript shim with a custom template.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.worker-build.extended;
  WorkerBuildModule = {
    options.programs.worker-build.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable worker-build.";
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
