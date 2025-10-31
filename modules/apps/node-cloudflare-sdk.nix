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
_:
let
  NodeCloudflareSdkModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."node-cloudflare-sdk".extended;
      packageSet = lib.attrByPath [ pkgs.system ] { } config.flake.packages;
      defaultPackage = lib.attrByPath [
        "node-cloudflare-src"
      ] (throw "node-cloudflare-src package not found for ${pkgs.system}") packageSet;
    in
    {
      options.programs."node-cloudflare-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Node Cloudflare SDK.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = lib.mdDoc "The Node Cloudflare SDK package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."node-cloudflare-sdk" = NodeCloudflareSdkModule;
}
