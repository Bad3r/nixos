/*
  Package: prefetch-yarn-deps
  Description: Helper that precomputes Yarn dependency hashes for reproducible Nix builds.
  Homepage: https://github.com/NixOS/nixpkgs
  Documentation: https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/node/fetch-yarn-deps/README.md
  Repository: https://github.com/NixOS/nixpkgs

  Summary:
    * Wraps the Yarn dependency graph scanner shipped with nixpkgs, emitting the sha256 needed for `fetchYarnDeps`.
    * Supports builder mode for CI use and integrates with `fetch-yarn-deps` workflows in Node/Electron derivations.

  Options:
    prefetch-yarn-deps <yarn.lock>: Produce the dependency hash for the given lockfile.
    prefetch-yarn-deps --builder <yarn.lock>: Emit only the hash, suitable for scripted builds.
    prefetch-yarn-deps --verbose <yarn.lock>: Print progress and cache hits while computing hashes.

  Example Usage:
    * `prefetch-yarn-deps yarn.lock` — Print the sha256 hash for a project lockfile.
    * `prefetch-yarn-deps --builder ./ui/yarn.lock` — Output just the hash for embedding in a derivation.
    * `nix run nixpkgs#prefetch-yarn-deps -- --verbose ./yarn.lock` — Execute via `nix run` with verbose logging.
*/
_:
let
  PrefetchYarnDepsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."prefetch-yarn-deps".extended;
    in
    {
      options.programs.prefetch-yarn-deps.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable prefetch-yarn-deps.";
        };

        package = lib.mkPackageOption pkgs "prefetch-yarn-deps" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.prefetch-yarn-deps = PrefetchYarnDepsModule;
}
