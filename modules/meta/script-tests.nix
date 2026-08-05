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
    run-packages-updaters = {
      dir = ../../tests/run-packages-updaters;
      subjects = [
        {
          src = ../../scripts/run-packages-updaters.sh;
          dest = "scripts/run-packages-updaters.sh";
        }
      ];
      extraInputs = _: [ ];
    };
    pr-comments-mgmt = {
      dir = ../../tests/pr-comments-mgmt;
      subjects = [
        {
          src = ../../scripts/gh-cli/pr-comments-mgmt.sh;
          dest = "scripts/gh-cli/pr-comments-mgmt.sh";
        }
      ];
      extraInputs = pkgs: [ pkgs.jq ];
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
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      wrapperInputsCheck =
        pkgs.runCommand "script-tests-prune-old-stashes-wrapper-inputs"
          {
            nativeBuildInputs = [ pkgs.git ];
          }
          ''
            export HOME="$PWD/home"
            mkdir -p "$HOME/repo"
            git -C "$HOME/repo" init -q -b main
            git -C "$HOME/repo" config user.email inputs@example.invalid
            git -C "$HOME/repo" config user.name "wrapper inputs check"
            : >"$HOME/repo/f"
            git -C "$HOME/repo" add f
            git -C "$HOME/repo" commit -q -m "initial commit"

            # A dry run reaches git, date and flock, which is the whole of
            # runtimeInputs. PATH is scrubbed so only the wrapper supplies them.
            cd "$HOME/repo"
            env -i \
              HOME="$HOME" \
              TMPDIR="$PWD" \
              XDG_RUNTIME_DIR="$PWD" \
              PATH=/nonexistent \
              ${config.packages.prune-old-stashes}/bin/prune-old-stashes --age 1d
            touch "$out"
          '';
    in
    {
      # The suites run the scripts directly with inputs supplied by this module,
      # so nothing they do exercises the wrapper's own runtimeInputs. Dropping
      # util-linux from it leaves every case passing while the wrapper fails at
      # the flock call for any user whose ambient PATH lacks it.
      checks = {
        script-tests-prune-old-stashes-wrapper-inputs = wrapperInputsCheck;
      }
      // lib.mapAttrs' (
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
