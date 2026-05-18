_: {
  flake.lib.meta.maintainedInputs = {
    nix-logseq-git-flake = {
      flakeInput = "nix-logseq-git-flake";
      upstream = {
        url = "https://github.com/Bad3r/nix-logseq-git-flake.git";
        ref = "main";
      };
      sourceMode = "local-override";
      local.pathEnv = "NIX_LOGSEQ_GIT_FLAKE_CHECKOUT";
      follows.nixpkgs = "nixpkgs";
      lockGraph.inputNames = [
        "flake-parts"
        "git-hooks"
        "import-tree"
        "nixpkgs"
      ];
      checks = [
        "clean-checkout"
        "reachable-commit"
        "tracked-files"
        "follows-preserved"
        "lock-graph"
        "no-local-url"
      ];
      notes = "Pilot input for local upstream patching through temporary --override-input evaluation.";
    };
  };
}
