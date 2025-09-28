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
    * `echo 'use flake' > .envrc && direnv allow` — Activate the current flake automatically when entering the directory.
    * `direnv exec .. nix shell nixpkgs#hello` — Run a command using another directory’s environment.
    * `direnv reload` — Re-evaluate the environment after editing `.envrc`.
*/

{
  flake.nixosModules.apps.direnv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.direnv ];
    };
}
