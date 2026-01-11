/*
  Package: nix-index-update
  Description: Downloads pre-generated indexes for nix-index to avoid local scraping.
  Homepage: https://github.com/nix-community/nix-index-database
  Documentation: https://github.com/nix-community/nix-index-database#usage
  Repository: https://github.com/nix-community/nix-index-database

  Summary:
    * Fetches cached nix-index databases for supported nixpkgs channels, dramatically speeding up `nix-locate` setup.
    * Handles channel detection automatically and stores indexes under `~/.cache/nix-index`.

  Options:
    nix-index-update: Download the latest index matching the current nixpkgs revision.
    nix-index-update --commit <rev>: Override detection and fetch a specific revision’s database.

  Example Usage:
    * `nix-index-update` — Pull the newest prebuilt index for your system and channels.
    * `nix-index-update --commit 1d9f84f4` — Force a particular nixpkgs revision for reproducibility.
*/
_:
let
  NixIndexUpdateModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-index-update".extended;
    in
    {
      options.programs.nix-index-update.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-index-update.";
        };

        package = lib.mkPackageOption pkgs "nix-index-update" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-index-update = NixIndexUpdateModule;
}
