/*
  Package: sss-pass-gpg-bootstrap
  Description: Repo-local helper that imports the signing key and initializes missing pass store metadata.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/tree/main/modules/home/pass-secret-service.nix
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Imports the repository signing key only after validating the expected fingerprint.
    * Initializes missing `.password-store/.gpg-id` state without rewriting existing pass recipients.

  Options:
    import-key: Validate and import a GPG secret key, then record ultimate trust.
    init-store: Initialize the pass store only when the directory or `.gpg-id` is missing.

  Notes:
    * This module is the source of truth for the helper package and Home Manager bootstrap wiring.
*/
{ config, ... }:
let
  inherit (config.flake.homeManagerModules)
    passGpgBootstrap
    ;

  SssPassGpgBootstrapModule =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."sss-pass-gpg-bootstrap".extended;
      hasHomeManager = lib.hasAttrByPath [ "home-manager" "sharedModules" ] options;
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

      config = lib.mkMerge [
        {
          # Must be unconditional so the package option can resolve without host overlays.
          nixpkgs.overlays = [
            (final: _prev: {
              "sss-pass-gpg-bootstrap" = final.callPackage ../../packages/sss-pass-gpg-bootstrap { };
            })
          ];
        }
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];
        })
        (lib.mkIf (cfg.enable && hasHomeManager) {
          home-manager.sharedModules = lib.mkAfter [ passGpgBootstrap ];
        })
      ];
    };
in
{
  flake.nixosModules.apps."sss-pass-gpg-bootstrap" = SssPassGpgBootstrapModule;
}
