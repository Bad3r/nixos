/*
  Package: nix-prefetch-git
  Description: Prefetches git repositories and prints hashes suitable for Nix fetchers.
  Homepage: https://github.com/NixOS/nixpkgs
  Documentation: https://nixos.org/manual/nix/stable/command-ref/nix-prefetch-git.html
  Repository: https://github.com/NixOS/nixpkgs

  Summary:
    * Clones a git repository at a specific revision and returns the sha256/SRI hash for use with `fetchGit` or `builtins.fetchGit`.
    * Supports submodules, shallow clones, and tarball output for reproducible packaging.

  Options:
    nix-prefetch-git <url> [--rev <rev>] [--branch <name>]: Prefetch a repo and print hash metadata.
    nix-prefetch-git --fetch-submodules <url>: Include submodules in the prefetch.
    nix-prefetch-git --nopull <path>: Reuse an existing clone without pulling.

  Example Usage:
    * `nix-prefetch-git https://github.com/nixos/nixpkgs --rev nixos-24.05` — Fetch the nixos-24.05 branch and print its hash.
    * `nix-prefetch-git --fetch-submodules https://github.com/example/project` — Include submodules when generating the hash.
    * `nix-prefetch-git --url . --rev refs/heads/main` — Prefetch a local repository.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nix-prefetch-git.extended;
  NixPrefetchGitModule = {
    options.programs.nix-prefetch-git.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable nix-prefetch-git.";
      };

      package = lib.mkPackageOption pkgs "nix-prefetch-git" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.nix-prefetch-git = NixPrefetchGitModule;
}
