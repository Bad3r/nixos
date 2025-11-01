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
      ...
    }:
    let
      cfg = config.programs."cloudflare-go-sdk".extended;
    in
    {
      options.programs."cloudflare-go-sdk".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc ''
            This module is a placeholder for the Cloudflare Go SDK.
            The SDK is a Go library installed via `go get github.com/cloudflare/cloudflare-go`,
            not a system package. Enabling this option has no effect.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Cloudflare Go SDK is a Go library, not a system package
        # Install it in your project with: go get github.com/cloudflare/cloudflare-go
      };
    };
in
{
  flake.nixosModules.apps."cloudflare-go-sdk" = CloudflareGoSdkModule;
}
