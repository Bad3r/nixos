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
    version: Print the library and tool version.
    genpkey: Generate a private key.
    s_client: Connect to a TLS service to debug the handshake.
*/
_:
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
          description = "Whether to enable openssl.";
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
