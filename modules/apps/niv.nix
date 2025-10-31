/*
  Package: niv
  Description: Nix dependency manager for pinning and updating project inputs via `sources.json`.
  Homepage: https://github.com/nmattia/niv
  Documentation: https://github.com/nmattia/niv#usage
  Repository: https://github.com/nmattia/niv

  Summary:
    * Provides commands to add, update, and list pinned Nix dependencies without editing Nix expressions directly.
    * Generates a `sources.nix` file for consumption by Nix expressions, enabling reproducible builds across machines.

  Options:
    niv init: Initialize `sources.json` and `sources.nix` in the current directory.
    niv add <owner>/<repo> --branch <branch>: Pin a GitHub repository.
    niv update [package]: Update all (or specific) dependencies to the latest version.
    niv drop <package>: Remove a pinned dependency.
    niv show [package]: Display current pin metadata.

  Example Usage:
    * `niv init` — Create the sources manifest for a new project.
    * `niv add nixpkgs -b nixos-24.05` — Pin a specific nixpkgs channel.
    * `niv update nixpkgs` — Fast-forward the nixpkgs input while preserving hashes.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.niv.extended;
  NivModule = {
    options.programs.niv.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable niv.";
      };

      package = lib.mkPackageOption pkgs "niv" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.niv = NivModule;
}
