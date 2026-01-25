/*
  Package: nix-index
  Description: Offline index and search utility for locating files in Nix packages.
  Homepage: https://github.com/nix-community/nix-index
  Documentation: https://github.com/nix-community/nix-index#usage
  Repository: https://github.com/nix-community/nix-index

  Summary:
    * Builds an index of the binary cache so you can quickly discover which package provides a file or command.
    * Integrates with shell completions and `nix-locate` for humans and scripts.

  Options:
    nix-index: Refresh the local index database (typically after `nix-index-update`).
    nix-locate <pattern>: Query the index for packages containing a file.

  Example Usage:
    * `nix-locate bin/terraform` -- Find which derivations ship a `terraform` binary.
    * `nix-index` -- Rebuild the index using the current substituter set.
*/
_:
let
  NixIndexModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-index".extended;
    in
    {
      options.programs.nix-index.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-index.";
        };

        package = lib.mkPackageOption pkgs "nix-index" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-index = NixIndexModule;
}
