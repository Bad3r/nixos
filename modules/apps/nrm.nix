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
  flake.nixosModules.apps.nrm =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodePackages.nrm ];
    };

}
