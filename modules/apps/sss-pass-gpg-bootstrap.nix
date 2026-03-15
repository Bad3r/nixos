/*
  Package: sss-pass-gpg-bootstrap
  Description: Repo-local helper that imports the signing key and repairs pass store metadata.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/tree/main/modules/home/pass-secret-service.nix
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Imports the repository signing key only after validating the expected fingerprint.
    * Repairs `.password-store/.gpg-id` drift before reinitializing the pass store.

  Options:
    import-key: Validate and import a GPG secret key, then record ultimate trust.
    init-store: Recreate `.gpg-id` state when the pass store is missing or misconfigured.

  Notes:
    * This package is also consumed internally by `home.passGpgBootstrap`; the app module exists so hosts can expose the helper explicitly when desired.
*/
_:
let
  SssPassGpgBootstrapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."sss-pass-gpg-bootstrap".extended;
    in
    {
      options.programs."sss-pass-gpg-bootstrap".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sss-pass-gpg-bootstrap.";
        };

        package = lib.mkPackageOption pkgs "sss-pass-gpg-bootstrap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."sss-pass-gpg-bootstrap" = SssPassGpgBootstrapModule;
}
