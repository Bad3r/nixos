# Module: home/base/nix-shell-keep-current-shell.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{ lib, ... }:
{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.zsh.shellAliases.nix-shell = "nix-shell --run ${lib.getExe pkgs.zsh}";
    };
}
