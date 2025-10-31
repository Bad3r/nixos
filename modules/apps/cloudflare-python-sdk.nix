/*
  Package: cloudflare-python-sdk
  Description: Python client bindings for the Cloudflare v4 API.
  Homepage: https://github.com/cloudflare/python-cloudflare
  Documentation: https://github.com/cloudflare/python-cloudflare#readme
  Repository: https://github.com/cloudflare/python-cloudflare

  Summary:
    * Wraps Cloudflare REST endpoints with Pythonic classes covering DNS, Workers, Zero Trust, and account resources.
    * Includes a bundled CLI and sample scripts to accelerate automation of common Cloudflare tasks.

  Options:
    cloudflare --help: Use the CLI entrypoint to explore available API commands.
    CloudFlare(token=<token>): Authenticate using Cloudflare API tokens within Python code.
    cf.zones.get(): Retrieve metadata for zones accessible to the authenticated account.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs."cloudflare-python-sdk".extended;
  CloudflarePythonSdkModule = {
    options.programs."cloudflare-python-sdk".extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable Cloudflare Python SDK.";
      };

      package = lib.mkPackageOption pkgs "cloudflare-python-sdk" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps."cloudflare-python-sdk" = CloudflarePythonSdkModule;
}
