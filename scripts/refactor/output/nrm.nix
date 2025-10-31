/*
  Package: nrm
  Description: npm registry manager for quickly switching between registries (npm, Yarn, cnpm, etc.).
  Homepage: https://github.com/Pana/nrm
  Documentation: https://github.com/Pana/nrm#usage
  Repository: https://github.com/Pana/nrm

  Summary:
    * Provides a CLI to list, switch, add, or remove npm registries, simplifying workflows for mirrors and private registries.
    * Supports testing registry response times and setting scoped registries for organizations.

  Options:
    nrm ls: List available registries and highlight the active one.
    nrm use <name>: Switch to a registered registry.
    nrm add <name> <url>: Add a custom registry entry.
    nrm del <name>: Remove a registry.
    nrm test: Benchmark the speed of all registries.

  Example Usage:
    * `nrm ls` — View all configured registries and the currently active registry.
    * `nrm use npm` — Switch back to the official npm registry.
    * `nrm add internal https://npm.company.com/` — Add a private corporate registry.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nodePackages.extended;
  NodePackagesModule = {
    options.programs.nodePackages.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable nodePackages.";
      };

      package = lib.mkPackageOption pkgs "nodePackages" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.nodePackages = NodePackagesModule;
}
