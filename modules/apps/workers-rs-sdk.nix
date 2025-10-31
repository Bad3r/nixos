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
      pkgs,
      ...
    }:
    let
      cfg = config.programs."workers-rs-sdk".extended;
      packageSet = lib.attrByPath [ pkgs.system ] { } config.flake.packages;
      defaultPackage = lib.attrByPath [
        "workers-rs-src"
      ] (throw "workers-rs-src package not found for ${pkgs.system}") packageSet;
    in
    {
      options.programs."workers-rs-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Workers Rust SDK.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = lib.mdDoc "The Workers Rust SDK package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."workers-rs-sdk" = WorkersRsSdkModule;
}
