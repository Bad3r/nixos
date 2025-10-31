/*
  Package: node-cloudflare-sdk
  Description: Official Node.js client for the Cloudflare v4 API.
  Homepage: https://github.com/cloudflare/node-cloudflare
  Documentation: https://github.com/cloudflare/node-cloudflare#readme
  Repository: https://github.com/cloudflare/node-cloudflare

  Summary:
    * Provides promise-based JavaScript helpers for DNS, Workers, KV, and account resources on Cloudflare.
    * Manages authentication tokens, pagination, and error handling for Node.js automation workflows.

  Options:
    npm install cloudflare: Add the SDK to a Node.js project using npm.
    const cf = new Cloudflare({ token }): Instantiate a client authenticated with an API token.
    cf.dnsRecords.browse(zoneId): List DNS records for a zone via the SDK.
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
