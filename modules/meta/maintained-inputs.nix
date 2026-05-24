_: {
  flake.lib.meta.maintainedInputs = {
    nixpkgs = {
      flakeInput = "nixpkgs";
      upstream = {
        url = "https://github.com/Bad3r/nixpkgs.git";
        ref = "master";
      };
      forkOf = {
        url = "https://github.com/NixOS/nixpkgs.git";
        ref = "master";
      };
      sourceMode = "submodule";
      checks = [
        "clean-checkout"
        "reachable-commit"
      ];
      notes = "Foundational package set tracked as a git submodule under inputs/nixpkgs. .gitmodules points at the Bad3r/nixpkgs fork (submodule origin) so the committed gitlink stays reachable for any in-progress patches; the local upstream remote points at NixOS/nixpkgs canonical for fetching new master commits and opening PRs. nixpkgs is a leaf input (no nested flake inputs), so follows and lockGraph.inputNames are not declared.";
    };
    home-manager = {
      flakeInput = "home-manager";
      upstream = {
        url = "https://github.com/Bad3r/home-manager.git";
        ref = "master";
      };
      forkOf = {
        url = "https://github.com/nix-community/home-manager.git";
        ref = "master";
      };
      sourceMode = "submodule";
      follows = {
        nixpkgs = "nixpkgs";
      };
      lockGraph.inputNames = [
        "nixpkgs"
      ];
      checks = [
        "clean-checkout"
        "reachable-commit"
        "follows-preserved"
        "lock-graph"
      ];
      notes = "Per-user configuration framework tracked as a git submodule under inputs/home-manager. .gitmodules points at the Bad3r/home-manager fork (submodule origin); the local upstream remote points at nix-community/home-manager canonical. home-manager's only nested input is nixpkgs, dedup'd through the root nixpkgs entry via follows.";
    };
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
