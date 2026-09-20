{
  flake.homeManagerModules.zsh = _: {
    # Authenticates Nix's GitHub fetches. `gh auth token` costs about 40 ms, so the value is cached
    # for the login session and revalidated in the background; a rotated token reaches the next shell.
    programs.zsh.initContent = ''
      () {
        emulate -L zsh
        setopt no_monitor
        (( $+commands[gh] )) || return 0

        local cache token line
        # A `su -p` root shell inherits XDG_RUNTIME_DIR; a cache written from there would be unreadable to its owner.
        [[ -n ''${XDG_RUNTIME_DIR-} && -O $XDG_RUNTIME_DIR ]] && cache=$XDG_RUNTIME_DIR/nix-github-token
        if [[ -n $cache && -r $cache ]]; then
          token=$(<$cache)
          {
            umask 077
            if gh auth token >| $cache.$$ 2>/dev/null; then
              command mv -f -- $cache.$$ $cache
            else
              command rm -f -- $cache.$$ $cache
            fi
          } &!
        else
          token=$(gh auth token 2>/dev/null) || return 0
          [[ -n $cache ]] && ( umask 077; print -r -- $token >| $cache )
        fi
        [[ -n $token ]] || return 0

        line="access-tokens = github.com=$token"
        [[ ''${NIX_CONFIG-} == *"$line"* ]] && return 0
        export NIX_CONFIG="''${NIX_CONFIG:+$NIX_CONFIG$'\n'}$line"
      }
    '';
  };
}
