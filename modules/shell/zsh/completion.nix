{
  flake.homeManagerModules.zsh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cacheDir = "${config.xdg.cacheHome}/zsh";
      groupColors = [
        "94"
        "32"
        "33"
        "35"
        "31"
        "38;5;27"
        "36"
        "38;5;100"
        "38;5;98"
        "91"
        "38;5;80"
        "92"
        "38;5;214"
        "38;5;165"
        "38;5;124"
        "38;5;120"
      ];
    in
    {
      programs.zsh = {
        # The only compinit for the owner: NixOS skips its global one (modules/base/shell-config.nix).
        completionInit = ''
          autoload -Uz compinit
          () {
            # Store paths are immutable, so an unchanged resolved fpath means an unchanged completion set.
            local dump=$1/zcompdump-$ZSH_VERSION sig=''${(j.:.)''${(@)fpath:A}}
            if [[ -r $dump && -r $dump.sig && $sig == "$(<$dump.sig)" ]]; then
              compinit -C -d $dump
            elif command mkdir -p -- $1 && [[ -O $1 ]]; then
              compinit -d $dump
              print -r -- $sig >| $dump.sig
              zcompile -- $dump
            else
              # Someone else's cache, as in a `su -p` root shell: complete without writing into it.
              compinit -D
            fi
          } ${lib.escapeShellArg cacheDir}
        '';

        initContent = lib.mkMerge [
          # fzf-tab has to be the last to bind Tab, so it follows fzf's own integration (910).
          (lib.mkOrder 920 ''
            source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
          '')

          ''
            zstyle ':completion:*:git-checkout:*' sort false
            # fzf-tab needs the bracketed description format to build groups.
            zstyle ':completion:*:descriptions' format '[%d]'
            zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
            zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"

            zstyle ':fzf-tab:*' switch-group ',' '.'
            zstyle ':fzf-tab:*' show-group full
            zstyle ':fzf-tab:*' group-colors ${
              lib.concatMapStringsSep " " (code: "$'\\033[${code}m'") groupColors
            }
            # Falls back to plain fzf outside tmux.
            zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
            zstyle ':fzf-tab:complete:cd:*' popup-pad 30 0
            zstyle ':fzf-tab:complete:cd:*' fzf-preview '${lib.getExe pkgs.eza} -1 --color=always $realpath'
            zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
              '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
            zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap
          ''
        ];
      };
    };
}
