/*
  Package: cloudflare-go-sdk
  Description: Official Go client library for the Cloudflare v4 API.
  Homepage: https://pkg.go.dev/github.com/cloudflare/cloudflare-go
  Documentation: https://pkg.go.dev/github.com/cloudflare/cloudflare-go
  Repository: https://github.com/cloudflare/cloudflare-go

  Summary:
    * Provides typed Go bindings for DNS, Workers, Zero Trust, Spectrum, and other Cloudflare services.
    * Simplifies authentication, pagination, and JSON handling when automating Cloudflare with Go.

  Options:
    go get github.com/cloudflare/cloudflare-go: Add the SDK to a Go module using Go modules.
    cloudflare.New(apiKey, email): Instantiate a client with global API key credentials.
    client.Zones(): Retrieve the zones accessible to the authenticated account.
*/
_:
let
  CloudflareGoSdkModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."cloudflare-go-sdk".extended;
      packageSet = lib.attrByPath [ pkgs.system ] { } config.flake.packages;
      defaultPackage = lib.attrByPath [
        "cloudflare-go-src"
      ] (throw "cloudflare-go-src package not found for ${pkgs.system}") packageSet;
    in
    {
      options.programs."cloudflare-go-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Cloudflare Go SDK.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = lib.mdDoc "The Cloudflare Go SDK package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."cloudflare-go-sdk" = CloudflareGoSdkModule;
}
