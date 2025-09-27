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
  flake.nixosModules.apps."node-cloudflare-sdk" =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      packageSet = lib.attrByPath [ pkgs.system ] { } config.flake.packages;
      sdkPackage = lib.attrByPath [
        "node-cloudflare-src"
      ] (throw "node-cloudflare-src package not found for ${pkgs.system}") packageSet;
    in
    {
      environment.systemPackages = [ sdkPackage ];
    };
}
