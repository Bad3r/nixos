# Module: home/base/shells/history.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base.programs.zsh = {
    history.ignorePatterns = [ "rm *" ];
    initContent = ''
      bindkey '^[;' up-line-or-search
      bindkey '^r' history-incremental-search-backward
    '';
  };
}
