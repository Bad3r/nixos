# Module: home/base/shells/syntax-highlighting.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base.programs.zsh.syntaxHighlighting = {
    enable = true;
    highlighters = [
      "main"
      "brackets"
      "pattern"
      "regexp"
      "cursor"
      "line"
    ];
  };
}
