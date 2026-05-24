_: {
  flake.lib.meta.maintainedInputs = {
    stylix = {
      flakeInput = "stylix";
      upstream = {
        url = "https://github.com/nix-community/stylix.git";
        ref = "master";
      };
      sourceMode = "local-override";
      local.pathEnv = "STYLIX_CHECKOUT";
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
      notes = "Theming framework maintained against an external checkout when patching upstream modules before publishing.";
    };
  };
}
