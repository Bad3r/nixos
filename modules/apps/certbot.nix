/*
  Package: certbot
  Description: ACME client that can obtain certs and extensibly update server configurations.
  Homepage: https://github.com/certbot/certbot
  Documentation: https://eff-certbot.readthedocs.io/
  Repository: https://github.com/certbot/certbot

  Summary:
    * Obtains and renews TLS certificates from ACME providers such as Let's Encrypt.
    * Supports standalone, webroot, DNS, and installer-based validation flows for automated certificate management.

  Options:
    certonly: Request or renew a certificate without installing it into a server config.
    renew: Attempt renewal for all configured certificates that are near expiry.
    revoke: Revoke an issued certificate and optionally clean up related local material.
    --dry-run: Exercise the renewal path against the ACME staging environment.
*/
_:
let
  CertbotModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.certbot.extended;
    in
    {
      options.programs.certbot.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable certbot.";
        };

        package = lib.mkPackageOption pkgs "certbot" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.certbot = CertbotModule;
}
