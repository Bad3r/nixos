# Module: home/base/shells/user-default.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{ lib, ... }:
{
  flake.modules = {
    nixos.base =
      { pkgs, ... }:
      {
        programs.zsh.enable = true;
        users.defaultUserShell = pkgs.zsh;
      };

    nixOnDroid.base =
      { pkgs, ... }:
      {
        user.shell = lib.getExe pkgs.zsh;
      };
  };
}
