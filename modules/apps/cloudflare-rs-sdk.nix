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
        default = false;
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
