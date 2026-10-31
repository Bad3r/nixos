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
    nix-prefetch-git --fetch-submodules <url>: Include submodules in the prefetch.
*/
_:
let
  NixPrefetchGitModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-prefetch-git".extended;
    in
    {
      options.programs.nix-prefetch-git.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-prefetch-git.";
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
