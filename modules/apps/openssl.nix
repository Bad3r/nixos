/*
  Package: openssl
  Description: Toolkit for Transport Layer Security (TLS) and cryptographic operations.
  Homepage: https://www.openssl.org/
  Documentation: https://docs.openssl.org/
  Repository: https://github.com/openssl/openssl

  Summary:
    * Provides the `openssl` command-line utility for managing keys, certificates, and cryptographic primitives.
    * Supplies the OpenSSL libraries used by applications that implement TLS/SSL and general-purpose cryptography.

  Options:
    version: Use `openssl version` to display the current library and tool version string.
    genpkey: Run `openssl genpkey -algorithm RSA -out key.pem` to generate private keys.
    s_client: Connect to TLS services with `openssl s_client -connect host:port` for debugging handshakes.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  OpensslModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.openssl.extended;
    in
    {
      options.programs.openssl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable openssl.";
        };

        package = lib.mkPackageOption pkgs "openssl" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.openssl = OpensslModule;
}
