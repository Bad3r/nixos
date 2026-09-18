{ inputs, ... }:
{
  flake.homeManagerModules.zsh =
    { lib, osConfig, ... }:
    let
      # The plugin stays inert without notify-send.
      notifySendAvailable = lib.attrByPath [ "programs" "libnotify" "extended" "enable" ] false osConfig;

      # Prefix-matched against the last command of a pipeline, after a leading `sudo` is dropped.
      ignoredCommands = [
        "vim"
        "nvim"
        "nano"
        "hx"
        "less"
        "more"
        "man"
        "bat"
        "batman"
        "tig"
        "lazygit"
        "lg"
        "lazydocker"
        "lzd"
        "watch"
        "top"
        "htop"
        "btm"
        "sysz"
        "ssh"
        "kssh"
        "kitty +kitten ssh"
        "tmux"
        "git commit"
        "git rebase"
        "journalctl"
        "systemctl status"
        "claude"
        "codex"
        "gemini"
        "nix develop"
        "nix shell"
        "nix repl"
        "nix-shell"
        "python"
        "ipython"
        "node"
        "bb"
        "sqlite3"
        "mpv"
        "fzf"
        "docker run"
        "docker exec"
      ];
    in
    {
      programs.zsh.initContent = lib.mkIf notifySendAvailable (
        lib.mkOrder 900 ''
          AUTO_NOTIFY_THRESHOLD=30
          AUTO_NOTIFY_IGNORE=(${lib.escapeShellArgs ignoredCommands})
          source ${inputs.zsh-auto-notify}/auto-notify.plugin.zsh
        ''
      );
    };
}
