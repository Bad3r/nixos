/*
  Shared zsh keybindings (edit-command-line + globalias).

  Both host zsh modules previously inlined the identical block; it now
  lives here and is appended to `programs.zsh.interactiveShellInit` via
  `lib.mkAfter` so per-host snippets still run first.

  Keybindings:
    * ^G in emacs/viins, and `v` in vicmd, opens the current buffer in
      `$VISUAL`/`$EDITOR` via the autoloaded `edit-command-line` widget.
      ^X^G remains bound to `list-expand` so the original chord is
      preserved.
    * SPACE expands aliases (and globs on a non-glob word), preserving
      variable refs verbatim. ^X SPACE forces full expansion. ^SPACE
      inserts a literal space without expansion.
*/
{
  flake.nixosModules.zshKeybindings =
    { lib, ... }:
    {
      programs.zsh.interactiveShellInit = lib.mkAfter ''
        # Edit the current command buffer in $VISUAL/$EDITOR.
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey '^X^G' list-expand
        bindkey '^G' edit-command-line
        bindkey -M vicmd '^X^G' list-expand
        bindkey -M vicmd '^G' edit-command-line
        bindkey -M vicmd v edit-command-line

        # Expand aliases on space; Don't expand globs (*.txt) or variable refs ($PWD)
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
        bindkey -M emacs " " globalias
        bindkey -M viins " " globalias
        # Ctrl-x Space forces alias, glob, and parameter expansion before inserting a space.
        bindkey -M emacs "^X " globalias-expand-all
        bindkey -M viins "^X " globalias-expand-all
        # Ctrl-space inserts a plain space without alias, glob, or parameter expansion.
        bindkey -M emacs "^ " magic-space
        bindkey -M viins "^ " magic-space
        bindkey -M isearch " " magic-space
      '';
    };
}
