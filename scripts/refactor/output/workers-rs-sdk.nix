/*
  Package: workers-rs-sdk
  Description: Rust SDK for authoring Cloudflare Workers with native bindings and tooling.
  Homepage: https://workers-rs.edgecompute.app/
  Documentation: https://workers-rs.edgecompute.app/
  Repository: https://github.com/cloudflare/workers-rs

  Summary:
    * Ships the `worker` Rust crates, macros, and examples used to build Cloudflare Workers entirely in Rust.
    * Integrates with `workers-build` and Wrangler to bundle WebAssembly, Durable Objects, and other runtime features.

  Options:
    --git https://github.com/cloudflare/workers-rs: Scaffold from the official template via `cargo generate --git …`.
    --features http: Enable compatibility layers when declaring `worker = { features = ["http"] }` in `Cargo.toml`.
    --release: Produce optimized wasm artifacts during `worker-build --release` builds.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.system.extended;
  SystemModule = {
    options.programs.system.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable system.";
      };

      package = lib.mkPackageOption pkgs "system" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.system = SystemModule;
}
