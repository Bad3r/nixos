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

{
  flake.nixosModules.apps."cloudflare-rs-sdk" =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      packageSet = lib.attrByPath [ pkgs.system ] { } config.flake.packages;
      sdkPackage = lib.attrByPath [
        "cloudflare-rs-src"
      ] (throw "cloudflare-rs-src package not found for ${pkgs.system}") packageSet;
    in
    {
      environment.systemPackages = [ sdkPackage ];
    };
}
