/*
  Package: cloudflare-python-sdk
  Description: Python client bindings for the Cloudflare v4 API.
  Homepage: https://github.com/cloudflare/python-cloudflare
  Documentation: https://github.com/cloudflare/python-cloudflare#readme
  Repository: https://github.com/cloudflare/cloudflare-python

  Summary:
    * Wraps Cloudflare REST endpoints with Pythonic classes covering DNS, Workers, Zero Trust, and account resources.
*/
_:
let
  CloudflarePythonSdkModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."cloudflare-python-sdk".extended;
    in
    {
      options.programs."cloudflare-python-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Cloudflare Python SDK.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "cloudflare" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."cloudflare-python-sdk" = CloudflarePythonSdkModule;
}
