/*
  Package: nix-prefetch-github
  Description: Helper for fetching GitHub repository tarballs and producing Nix sha256 hashes.
  Homepage: https://github.com/madjar/nix-prefetch-github
  Documentation: https://github.com/madjar/nix-prefetch-github#usage
  Repository: https://github.com/seppeljordan/nix-prefetch-github

  Summary:
    * Downloads GitHub repositories (with optional revision, branch, or submodules) and prints Nix-friendly hash values for use in derivations.
    * Supports JSON output for direct use in scripts when updating `fetchFromGitHub` sources.

  Options:
    --fetch-submodules: Include git submodules when computing the hash.
    --json: Emit the results as JSON.
    --nix: Output a Nix expression snippet referencing the fetched source.
*/
_:
let
  NixPrefetchGithubModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-prefetch-github".extended;
    in
    {
      options.programs.nix-prefetch-github.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-prefetch-github.";
        };

        package = lib.mkPackageOption pkgs "nix-prefetch-github" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-prefetch-github = NixPrefetchGithubModule;
}
