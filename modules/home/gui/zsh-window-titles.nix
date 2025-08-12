# Module: home/gui/zsh-window-titles.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.gui
# Pattern: Home Manager GUI - Graphical application configuration

# modules/window-titles.nix

{
  flake.modules.homeManager.gui.programs.zsh.initContent = ''
    precmd() {
      local cwd
      cwd=''${PWD/#$HOME/\~}
      print -Pn "\e]0;zsh ''${cwd}\a"
    }
  '';
}
