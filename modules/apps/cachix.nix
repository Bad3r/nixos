/*
  Package: cachix
  Description: CLI client for managing Cachix binary caches used by Nix projects.
  Homepage: https://cachix.org
  Documentation: https://docs.cachix.org/cli-reference.html
  Repository: https://github.com/cachix/cachix

  Summary:
    * Lets you push builds to Cachix caches, configure substituters, and manage cache secrets.
    * Integrates with CI and local workflows to share build artefacts across machines.

  Options:
    cachix use <name>: Configure the current system to trust a Cachix cache.
    cachix push <name> <path>: Upload store paths to a cache.
    cachix watch-store <name>: Automatically push new builds as they appear.

  Example Usage:
    * `cachix use myteam` — Add the `myteam` cache to `/etc/nix/nix.conf` and trust its key.
    * `cachix push myteam result` — Upload a built derivation to share with teammates.
    * `cachix watch-store myteam` — Continuously push builds while iterating locally.
*/
_:
let
  CachixModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cachix.extended;
    in
    {
      options.programs.cachix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable cachix.";
        };

        package = lib.mkPackageOption pkgs "cachix" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cachix = CachixModule;
}
