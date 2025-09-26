/*
  Package: nix-prefetch-github
  Description: Helper for fetching GitHub repository tarballs and producing Nix sha256 hashes.
  Homepage: https://github.com/madjar/nix-prefetch-github
  Documentation: https://github.com/madjar/nix-prefetch-github#usage
  Repository: https://github.com/madjar/nix-prefetch-github

  Summary:
    * Downloads GitHub repositories (with optional revision, branch, or submodules) and prints Nix-friendly hash values for use in derivations.
    * Supports JSON output for direct use in scripts when updating `fetchFromGitHub` sources.

  Options:
    nix-prefetch-github <owner> <repo> [rev]: Fetch a repository at the given revision (branch/tag/commit).
    --fetch-submodules: Include git submodules when computing the hash.
    --json: Emit metadata as JSON (URL, sha256, rev).
    --nix: Output a Nix expression snippet referencing the fetched source.

  Example Usage:
    * `nix-prefetch-github NixOS nixpkgs --rev nixos-24.05` — Prefetch the nixpkgs channel and print sha256.
    * `nix-prefetch-github owner repo --fetch-submodules --json` — Get hash data for a repo including submodules in JSON form.
    * `nix-prefetch-github madjar nix-prefetch-github --nix` — Generate a ready-to-paste Nix snippet for the tool itself.
*/

{
  flake.nixosModules.apps."nix-prefetch-github" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nix-prefetch-github ];
    };

}
