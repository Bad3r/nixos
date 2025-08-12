# Module: home/base/zsh-keymap.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

# modules/zsh-keymap.nix

{
  # Possible values:
  # emacs = "bindkey -e";
  # viins = "bindkey -v";
  # vicmd = "bindkey -a";
  flake.modules.homeManager.base.programs.zsh.defaultKeymap = "viins";

}
