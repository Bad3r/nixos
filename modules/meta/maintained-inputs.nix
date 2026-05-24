_: {
  flake.lib.meta.maintainedInputs = {
    stylix = {
      flakeInput = "stylix";
      upstream = {
        url = "https://github.com/Bad3r/stylix.git";
        ref = "master";
      };
      forkOf = {
        url = "https://github.com/nix-community/stylix.git";
        ref = "master";
      };
      sourceMode = "submodule";
      follows = {
        flake-parts = "flake-parts";
        nixpkgs = "nixpkgs";
        nur = "dedupe_nur";
        systems = "systems";
        tinted-schemes = "tinted-schemes";
      };
      lockGraph.inputNames = [
        "base16"
        "base16-fish"
        "base16-helix"
        "base16-vim"
        "firefox-gnome-theme"
        "flake-parts"
        "gnome-shell"
        "nixpkgs"
        "nur"
        "systems"
        "tinted-kitty"
        "tinted-schemes"
        "tinted-tmux"
        "tinted-zed"
      ];
      checks = [
        "clean-checkout"
        "reachable-commit"
        "follows-preserved"
        "lock-graph"
      ];
      notes = "Theming framework tracked as a git submodule under inputs/stylix. .gitmodules points at the Bad3r/stylix fork (submodule origin) so the committed gitlink stays reachable even for WIP patches; the local upstream remote points at the nix-community/stylix canonical source for fetching new upstream master commits and opening PRs.";
    };
  };
}
