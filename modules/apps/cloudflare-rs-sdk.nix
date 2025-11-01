/*
  Package: cloudflare-rs-sdk
  Description: Rust client library for the Cloudflare v4 API.
  Homepage: https://github.com/cloudflare/cloudflare-rs
  Documentation: https://docs.rs/cloudflare/latest/cloudflare/
  Repository: https://github.com/cloudflare/cloudflare-rs

  Summary:
    * Exposes strongly typed Rust bindings for DNS, Workers KV, R2, and account-level Cloudflare services.
    * Supports async execution with Tokio and handles pagination, authentication, and rate limiting helpers.

  Options:
    cargo add cloudflare: Add the SDK crate to a Rust project using Cargo.
    Client::new(api_token): Construct an authenticated API client with a scoped token.
    client.zones().list(): List zones accessible to the configured account.
*/
_:
let
  CloudflareRsSdkModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs."cloudflare-rs-sdk".extended;
    in
    {
      options.programs."cloudflare-rs-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc ''
            This module is a placeholder for the Cloudflare Rust SDK.
            The SDK is a Rust crate installed via `cargo add cloudflare`,
            not a system package. Enabling this option has no effect.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Cloudflare Rust SDK is a Rust crate, not a system package
        # Install it in your project with: cargo add cloudflare
      };
    };
in
{
  flake.nixosModules.apps."cloudflare-rs-sdk" = CloudflareRsSdkModule;
}
