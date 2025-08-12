# Module: home/base/shells/editing.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base.programs.zsh.initContent = ''
    bindkey '^w' backward-kill-word

    autoload -Uz edit-command-line
    zle -N edit-command-line
    bindkey -M vicmd '^e' edit-command-line
  '';
}
