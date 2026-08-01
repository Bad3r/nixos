# Runs the shell test suites under tests/ as flake checks. Without this nothing
# executes them: their whole value is mutation-regression against the scripts
# they guard, which lapses silently on the first refactor otherwise.
_:
let
  suites = {
    prune-old-stashes = {
      dir = ../../tests/prune-old-stashes;
      scripts = [ "prune-old-stashes.sh" ];
      extraInputs = pkgs: [ pkgs.util-linux ];
    };
    prune-stale-worktrees = {
      dir = ../../tests/prune-stale-worktrees;
      scripts = [
        "prune-stale-worktrees.sh"
        "git-worktree-remove-safe.sh"
      ];
      extraInputs = pkgs: [
        pkgs.util-linux
        pkgs.jq
        pkgs.gnused
      ];
    };
  };
in
{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks = lib.mapAttrs' (
        name: suite:
        lib.nameValuePair "script-tests-${name}" (
          pkgs.runCommand "script-tests-${name}"
            {
              nativeBuildInputs =
                (with pkgs; [
                  bash
                  coreutils
                  git
                ])
                ++ suite.extraInputs pkgs;
            }
            ''
              mkdir -p tests scripts
              cp -r ${suite.dir} tests/${name}
              ${lib.concatMapStringsSep "\n" (s: ''
                install -Dm755 ${../../scripts}/${s} scripts/${s}
              '') suite.scripts}
              # No /usr/bin/env in the build sandbox.
              patchShebangs scripts
              # The suites resolve their subject as $SCRIPT_DIR/../../scripts/<name>.
              export HOME="$PWD/home"
              mkdir -p "$HOME"
              bash tests/${name}/run.sh
              touch "$out"
            ''
        )
      ) suites;
    };
}
