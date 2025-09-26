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
  flake.nixosModules.apps.niv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.niv ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.niv ];
    };
}
