# modules/common/home.nix
{ config, ... }:

{

  home.stateVersion = "24.11";

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    GIT_EDITOR = "nvim";
  };

  home.shellAliases = {
    vi = "nvim";
    vim = "nvim";
    v = "nvim";
  };

  programs.zsh.sessionVariables = {
    ZDOTDIR = "${config.xdg.configHome}/zsh";
  };

  home.file.".bashrc".text = ''
    sudoKate() {
    if [ $# -eq 0 ]; then
        echo "Usage: sudoKate <file-or-directory> [more args...]"
        return 1
    fi
    sudo env -u SUDO_USER -u KDESU_USER \
        DISPLAY="$DISPLAY" \
        XAUTHORITY="$XAUTHORITY" \
        kate "$@"
    }

    # GPG
    export GPG_TTY=$(tty)
  '';

  home.file.".zshrc".text = ''
    # GPG
    export GPG_TTY=$(tty)
  '';

  #   programs.vscode = {
  #     enable = true;
  #     package = pkgs.vscode-fhs; # Use FHS environment for better extension compatibility
  #     profiles.default.extensions = with pkgs.vscode-extensions; [
  #       ms-python.python
  #       ms-vscode.cpptools
  #       jnoortheen.nix-ide
  #       eamodio.gitlens
  #     ];
  #     profiles.default.userSettings = {
  #       "editor.fontSize" = 14;
  #       "files.autoSave" = "afterDelay";
  #       "window.zoomLevel" = 1;
  #     };
  #   };
}
