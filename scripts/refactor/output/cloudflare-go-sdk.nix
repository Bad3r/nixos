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
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
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
