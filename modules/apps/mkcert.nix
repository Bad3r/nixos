/*
  Package: mkcert
  Description: Simple tool for making locally-trusted development certificates.
  Homepage: https://github.com/FiloSottile/mkcert
  Documentation: https://github.com/FiloSottile/mkcert
  Repository: https://github.com/FiloSottile/mkcert

  Summary:
    * Creates locally trusted development certificates without relying on a public CA.
    * Installs and manages a local root CA for browser and service testing workflows.

  Options:
    -install: Install the local CA into the system trust stores.
    -uninstall: Remove the local CA from the system trust stores.
    -cert-file: Write the leaf certificate to a specific output path.
*/
_:
let
  MkcertModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mkcert.extended;
    in
    {
      options.programs.mkcert.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mkcert.";
        };

        package = lib.mkPackageOption pkgs "mkcert" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mkcert = MkcertModule;
}
