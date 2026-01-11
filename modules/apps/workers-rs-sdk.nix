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
_:
let
  WorkersRsSdkModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs."workers-rs-sdk".extended;
    in
    {
      options.programs."workers-rs-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            This module is a placeholder for the Cloudflare Workers Rust SDK.
            The SDK is a Rust crate installed via `cargo add worker`,
            not a system package. Enabling this option has no effect.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Workers Rust SDK is a Rust crate, not a system package
        # Install it in your project with: cargo add worker
      };
    };
in
{
  flake.nixosModules.apps."workers-rs-sdk" = WorkersRsSdkModule;
}
