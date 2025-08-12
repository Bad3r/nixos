# Module: home/base/shells/completion.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{ lib, ... }:
{
  flake.modules.homeManager.base.programs.zsh = {
    enableCompletion = true;
    initContent = lib.mkOrder 550 ''
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
    '';
  };
}
