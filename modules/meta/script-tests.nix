# Runs the shell test suites under tests/ as flake checks. Without this nothing
# executes them: their whole value is mutation-regression against the scripts
# they guard, which lapses silently on the first refactor otherwise.
#
# Registering here is necessary but not sufficient: `nix flake check --no-build`
# and the CI "Check flake" step only force each check's drvPath. The "Run script
# test suites" step in .github/workflows/check.yml builds these by name, which
# is what actually executes them.
_:
let
  # Each suite resolves its subject relative to its own directory, so `dest` is
  # the path under the build root that the harness expects to find.
  suites = {
    prune-old-stashes = {
      dir = ../../tests/prune-old-stashes;
      subjects = [
        {
          src = ../../scripts/prune-old-stashes.sh;
          dest = "scripts/prune-old-stashes.sh";
        }
      ];
      extraInputs = pkgs: [ pkgs.util-linux ];
    };
    prune-stale-worktrees = {
      dir = ../../tests/prune-stale-worktrees;
      subjects = [
        {
          src = ../../scripts/prune-stale-worktrees.sh;
          dest = "scripts/prune-stale-worktrees.sh";
        }
        {
          src = ../../scripts/git-worktree-remove-safe.sh;
          dest = "scripts/git-worktree-remove-safe.sh";
        }
      ];
      extraInputs = pkgs: [
        pkgs.util-linux
        pkgs.jq
        pkgs.gnused
      ];
    };
    git-worktree-remove-safe = {
      dir = ../../tests/git-worktree-remove-safe;
      subjects = [
        {
          src = ../../scripts/git-worktree-remove-safe.sh;
          dest = "scripts/git-worktree-remove-safe.sh";
        }
      ];
      extraInputs = _: [ ];
    };
    ci-upstream-tracker = {
      dir = ../../tests/ci-upstream-tracker;
      subjects = [
        {
          src = ../../.github/scripts/upstream-tracker.sh;
          dest = ".github/scripts/upstream-tracker.sh";
        }
      ];
      extraInputs = pkgs: [
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
              mkdir -p tests
              cp -r ${suite.dir} tests/${name}
              ${lib.concatMapStringsSep "\n" (s: ''
                install -Dm755 ${s.src} ${s.dest}
              '') suite.subjects}
              # No /usr/bin/env in the build sandbox.
              patchShebangs ${lib.concatMapStringsSep " " (s: s.dest) suite.subjects}
              export HOME="$PWD/home"
              mkdir -p "$HOME"
              bash tests/${name}/run.sh
              touch "$out"
            ''
        )
      ) suites;
    };
}
