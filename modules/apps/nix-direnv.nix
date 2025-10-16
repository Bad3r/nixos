/*
  Package: nix-direnv
  Description: Fast `use_nix` implementation for direnv with persistent build results.
  Homepage: https://github.com/nix-community/nix-direnv
  Documentation: https://github.com/nix-community/nix-direnv#readme
  Repository: https://github.com/nix-community/nix-direnv

  Summary:
    * Speeds up direnv integration by caching derivations and avoiding redundant evaluations.
    * Supports flakes via `use flake` and backwards-compatible `use nix` semantics.

  Options:
    use_nix: In `.envrc`, load the environment described by `shell.nix`.
    use flake [flake-uri]: Activate a flake-based devShell (defaults to `.`).

  Example Usage:
    * `.envrc`: `use flake` — Automatically enter the project dev shell using flakes.
    * `.envrc`: `use_nix` — Fallback to classic `shell.nix` evaluation with caching.
*/

{
  flake.nixosModules.apps."nix-direnv" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-direnv" ];
    };
}
