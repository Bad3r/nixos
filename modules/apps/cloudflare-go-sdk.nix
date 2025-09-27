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
  flake.nixosModules.apps."cloudflare-go-sdk" =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      packageSet = lib.attrByPath [ pkgs.system ] { } config.flake.packages;
      sdkPackage = lib.attrByPath [
        "cloudflare-go-src"
      ] (throw "cloudflare-go-src package not found for ${pkgs.system}") packageSet;
    in
    {
      environment.systemPackages = [ sdkPackage ];
    };
}
