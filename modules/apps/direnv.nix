/*
  Package: direnv
  Description: Shell extension that loads/unloads environment variables based on the current directory.
  Homepage: https://direnv.net
  Documentation: https://direnv.net/#usage
  Repository: https://github.com/direnv/direnv

  Summary:
    * Hooks into your shell to watch `.envrc` files and adjust environment variables automatically.
    * Integrates with `nix-direnv` for fast, cache-aware Nix environment activation.

  Options:
    direnv allow: Authorize the current `.envrc` file.
    direnv deny: Revert authorization for a directory.
    direnv exec <dir> <command>: Execute a command within another directory’s environment.

  Example Usage:
    * `echo 'use flake' > .envrc {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} direnv allow` — Activate the current flake automatically when entering the directory.
    * `direnv exec .. nix shell nixpkgs#hello` — Run a command using another directory’s environment.
    * `direnv reload` — Re-evaluate the environment after editing `.envrc`.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  DirenvModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.direnv.extended;
    in
    {
      options.programs.direnv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable direnv.";
        };

        package = lib.mkPackageOption pkgs "direnv" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.direnv = DirenvModule;
}
