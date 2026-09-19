{
  flake.homeManagerModules.zsh =
    { lib, ... }:
    {
      # 1050: after the tool integrations (fzf 910, atuin 1000) so these win, before syntax highlighting (1200).
      programs.zsh.initContent = lib.mkOrder 1050 ''
        # Prefix history search on the arrows and on ^K/^J.
        autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
        zle -N up-line-or-beginning-search
        zle -N down-line-or-beginning-search
        bindkey '^[[A' up-line-or-beginning-search
        bindkey '^[[B' down-line-or-beginning-search
        # /etc/zinputrc keeps zle in application mode, where the arrows send the terminfo sequences instead.
        [[ -n ''${terminfo[kcuu1]} ]] && bindkey "''${terminfo[kcuu1]}" up-line-or-beginning-search
        [[ -n ''${terminfo[kcud1]} ]] && bindkey "''${terminfo[kcud1]}" down-line-or-beginning-search
        bindkey '^K' up-line-or-beginning-search
        bindkey '^J' down-line-or-beginning-search

        bindkey '^H' backward-word
        bindkey '^L' forward-word
        bindkey '^U' backward-kill-word
        bindkey '^W' backward-kill-word

        # ^G (and v in vicmd) edits the buffer in $VISUAL; ^X^G keeps list-expand reachable.
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey '^X^G' list-expand
        bindkey '^G' edit-command-line
        bindkey -M vicmd '^X^G' list-expand
        bindkey -M vicmd '^G' edit-command-line
        bindkey -M vicmd v edit-command-line

        # Space expands aliases, and globs unless the word holds * or $.
        globalias() {
          zle _expand_alias

          local current_word="''${LBUFFER##*[[:space:]]}"
          if [[ $current_word != *[\*\$]* ]]; then
            zle expand-word
          fi

          zle self-insert
        }
        globalias-expand-all() {
          zle _expand_alias
          zle expand-word
          zle self-insert
        }
        zle -N globalias
        zle -N globalias-expand-all
        bindkey -M emacs ' ' globalias
        bindkey -M viins ' ' globalias
        # ^X Space forces full expansion; ^Space inserts a plain space.
        bindkey -M emacs '^X ' globalias-expand-all
        bindkey -M viins '^X ' globalias-expand-all
        bindkey -M emacs '^ ' magic-space
        bindkey -M viins '^ ' magic-space
        bindkey -M isearch ' ' magic-space

        # ^N replaces the shell with a fresh one.
        exec-zsh() {
          zle -I
          exec zsh <"$TTY"
        }
        zle -N exec-zsh
        bindkey '^N' exec-zsh
      '';
    };
}
