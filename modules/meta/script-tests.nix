# Runs the shell test suites under tests/ as flake checks. Without this nothing
# executes them: their whole value is mutation-regression against the scripts
# they guard, which lapses silently on the first refactor otherwise.
#
# Registering here is necessary but not sufficient: `nix flake check --no-build`
# and the CI "Check flake" step only force each check's drvPath. The "Run
# runtime check suites" step in .github/workflows/check.yml builds these by
# name, which is what actually executes them: it selects on the script-tests-
# prefix or on passthru.runtimeCheck, so anything named here is picked up
# without a workflow edit.
_:
let
  # Each suite resolves its subject relative to its own directory, so `dest` is
  # the path under the build root that the harness expects to find.
  #
  # extraInputs declares every external the harness or its subjects invoke past
  # the bash/coreutils/git floor below. stdenv puts gnused, gnugrep and gawk on
  # PATH regardless, so an omission of those three passes here and fails only
  # wherever the script runs without them; util-linux and jq are the ones that
  # break the check itself. Declaring all of them keeps the list a readable
  # inventory of what a suite needs rather than of what stdenv forgot.
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
      extraInputs = pkgs: [ pkgs.gnused ];
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
    flake-ref = {
      dir = ../../tests/flake-ref;
      subjects = [
        {
          src = ../../scripts/lib/flake-ref.sh;
          dest = "scripts/lib/flake-ref.sh";
        }
      ];
      # The subject runs no external at all, and the suite reaches git only to
      # let `git worktree add` produce the marker its branch turns on.
      extraInputs = _: [ ];
    };
    secrets-guard = {
      dir = ../../tests/secrets-guard;
      subjects = [
        {
          src = ../../scripts/lib/secrets-guard.sh;
          dest = "scripts/lib/secrets-guard.sh";
        }
      ];
      extraInputs = pkgs: [
        pkgs.gnugrep
        pkgs.gawk
        pkgs.gnused
      ];
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

      cacheCoverageWrapperInputsCheck =
        pkgs.runCommand "script-tests-cache-coverage-wrapper-inputs"
          {
            nativeBuildInputs = [ pkgs.git ];
          }
          ''
            export HOME="$PWD/home"
            mkdir -p "$HOME/repo"
            git -C "$HOME/repo" init -q -b main
            git -C "$HOME/repo" config user.email inputs@example.invalid
            git -C "$HOME/repo" config user.name "wrapper inputs check"

            # The ten patterns secrets_guard_paths requires under the heading,
            # not the rest of what modules/development/gitignore.nix generates:
            # the parser fails closed on a thinned block, so a shorter fixture
            # would test that branch instead of the scan.
            printf '%s\n' \
              '# Secrets safety (defense-in-depth)' \
              '*.agekey' '*.key' '*.pem' '*.p12' '*.pfx' \
              '.env' '.env.*' 'id_*' 'decrypted_*' '*.dec.*' \
              >"$HOME/repo/.gitignore"
            : >"$HOME/repo/flake.nix"
            : >"$HOME/repo/flake.lock"
            git -C "$HOME/repo" add .gitignore flake.nix flake.lock
            git -C "$HOME/repo" commit -q -m "initial commit"
            # Untracked and matched by id_*, so the scan has something to find.
            : >"$HOME/repo/id_ed25519"

            # --allow-dirty selects the path: ref, and the guard aborts before
            # the script reads flake.lock or calls nix, so this reaches grep,
            # awk and mktemp with no evaluation and no network. flake.nix and
            # flake.lock only have to exist to clear the checks ahead of it.
            #
            # PATH is scrubbed because writeShellApplication exports
            # "<runtimeInputs>:$PATH" rather than replacing it, so an ordinary
            # run resolves a dropped tool from whatever the caller carried. grep
            # went missing exactly that way until 0c10b942 caught it by hand,
            # and it is the worst one to lose: the guard used to skip its
            # discriminator silently rather than fail.
            #
            # Both a hit and an inoperative guard exit 2 here, since neither is
            # a coverage result, so the exit code alone cannot tell them apart;
            # stderr does.
            set +e
            env -i \
              HOME="$HOME" \
              TMPDIR="$PWD" \
              PATH=/nonexistent \
              ${config.packages.cache-coverage}/bin/cache-coverage \
              --flake-dir "$HOME/repo" --allow-dirty \
              >stdout.log 2>stderr.log
            rc=$?
            set -e

            if [ "$rc" -ne 2 ]; then
              echo "expected exit 2 from the guard abort, got $rc" >&2
              cat stderr.log >&2
              exit 1
            fi
            if ! grep -q 'id_ed25519' stderr.log; then
              echo "the guard did not name the untracked probe, so the scan did not run to completion" >&2
              cat stderr.log >&2
              exit 1
            fi
            if grep -q 'the secrets guard cannot run' stderr.log; then
              echo "the guard reported itself inoperative instead of scanning" >&2
              cat stderr.log >&2
              exit 1
            fi
            touch "$out"
          '';
      # The minimum set named in secrets_guard_paths is the guard's coupling to
      # modules/development/gitignore.nix, and every other fixture that reaches
      # the parser is a hand-written copy of the block, so the suite passes
      # whatever the generator emits. Dropping or renaming one pattern there
      # leaves managed-files-synced green, since .gitignore still matches its
      # source, and leaves the suite green on its own copy; the guard then trips
      # the minimum-set branch on every real run and the documented way past it
      # turns the control off. This reads the committed file the guard actually
      # parses, which managed-files-synced already pins to the generator.
      gitignoreContractCheck =
        pkgs.runCommand "script-tests-secrets-guard-gitignore-contract"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              git
              gnugrep
              gawk
            ];
          }
          ''
            export HOME="$PWD/home"
            mkdir -p "$HOME" repo
            git -C repo init -q -b main
            git -C repo config user.email contract@example.invalid
            git -C repo config user.name "gitignore contract"
            cp ${../../.gitignore} repo/.gitignore
            git -C repo add .gitignore
            git -C repo commit -q -m "the committed .gitignore"

            # One untracked probe per required pattern, plus the public key the
            # block negates: presence in the deny list is what the parser
            # asserts, and these assert the patterns still match something.
            touch repo/probe.agekey repo/probe.key repo/probe.pem \
              repo/probe.p12 repo/probe.pfx repo/.env repo/.env.local \
              repo/id_probe repo/id_probe.pub \
              repo/decrypted_probe.yaml repo/probe.dec.txt

            source ${../../scripts/lib/secrets-guard.sh}
            rc=0
            secrets_guard_paths repo >hits.bin 2>err.log || rc=$?
            if [ "$rc" -ne 0 ]; then
              echo "the guard could not parse the committed .gitignore (rc $rc); its minimum set and modules/development/gitignore.nix have diverged" >&2
              cat err.log >&2
              exit 1
            fi
            tr '\0' '\n' <hits.bin >hits.txt
            for probe in probe.agekey probe.key probe.pem probe.p12 probe.pfx \
              .env .env.local id_probe decrypted_probe.yaml probe.dec.txt; do
              if ! grep -qxF "$probe" hits.txt; then
                echo "the block no longer matches $probe, so a pattern the guard requires has changed meaning" >&2
                cat hits.txt >&2
                exit 1
              fi
            done
            if grep -qxF id_probe.pub hits.txt; then
              echo "the block's !id_*.pub negation no longer applies" >&2
              exit 1
            fi
            touch "$out"
          '';
    in
    {
      # The suites run the scripts directly with inputs supplied by this module,
      # so nothing they do exercises the wrapper's own runtimeInputs. Dropping
      # util-linux from it leaves every case passing while the wrapper fails at
      # the flock call for any user whose ambient PATH lacks it. The
      # cache-coverage wrapper carries the same exposure through the guard text
      # prepended to it, whose tools no suite reaches either.
      checks = {
        script-tests-prune-old-stashes-wrapper-inputs = wrapperInputsCheck;
        script-tests-cache-coverage-wrapper-inputs = cacheCoverageWrapperInputsCheck;
        script-tests-secrets-guard-gitignore-contract = gitignoreContractCheck;
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
