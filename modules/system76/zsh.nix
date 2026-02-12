{
  configurations.nixos.system76.module = {
    programs.zsh = {
      enable = true;
      interactiveShellInit = ''
        # Source Home Manager session variables from per-user profile path.
        source "/etc/profiles/per-user/vx/etc/profile.d/hm-session-vars.sh"

        # Nix CLI config export disabled in interactive shell.
        # Exporting multiline NIX_CONFIG here can break nh elevation with:
        #   env: 'nix-command': No such file or directory
        # Keep build-time Nix config in build.sh/flake nixConfig instead.
        # NIX_CONFIG="experimental-features = nix-command flakes pipe-operators
        # accept-flake-config = true
        # allow-import-from-derivation = false
        # abort-on-warn = false"
        # if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        #   NIX_CONFIG+="
        # access-tokens = github.com=$(gh auth token)"
        # fi
        # export NIX_CONFIG

        # Mirror bash behavior: expose hostname through HOSTNAME in zsh.
        export HOSTNAME="$HOST"

        setopt NO_INTERACTIVE_COMMENTS
        alias nr='nix run nixpkgs#'
        alias ns='nix shell nixpkgs#'
        alias np='nix profile install nixpkgs#'
      '';
    };
  };
}
