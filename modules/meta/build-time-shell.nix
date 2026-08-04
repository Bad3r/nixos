/*
  Check: build-time shell text avoids programmable-completion builtins.

  The bash a runCommand builder runs is built without programmable completion,
  so `compgen` is not a builtin there, it is an unresolved command. In a
  condition context that difference is silent rather than fatal: an assertion
  whose condition is a `compgen -G` call takes its else branch and reports a
  pass on every run, which is how a leftover-temporary assertion in
  modules/browsers/firefoxpwa/m365-check.nix checked nothing while looking
  green. `declare -F`, `declare -p` and a `shopt -s nullglob` array are plain
  builtins and cover the same ground.

  Scoped to the trees whose shell text a Nix build executes. scripts/ runs under
  the user's own bash, where the builtin exists.

  Matched at command positions only, so the prose in this file and in the
  comments that explain the rule are not themselves hits, and planted against a
  fixture before the tree is scanned: a detector that cannot report a hit is the
  same defect this guards against.
*/
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      sources = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          (lib.fileset.fileFilter (file: file.hasExt "nix") ../../modules)
          (lib.fileset.fileFilter (file: file.hasExt "nix") ../../packages)
          (lib.fileset.fileFilter (file: file.hasExt "sh") ../../tests)
        ];
      };
    in
    {
      checks.build-time-shell =
        pkgs.runCommand "build-time-shell-check"
          {
            # Opts this check into the runtime build step in
            # .github/workflows/check.yml, which otherwise only forces drvPaths.
            passthru.runtimeCheck = true;
            nativeBuildInputs = [ pkgs.gnugrep ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            # The optional ! keeps the anchoring at a command position while
            # admitting the negated spelling of it, which fails open the same
            # way and is the more natural way to write an assertion that wants
            # to report a leftover. Spelled with the negation inline rather than
            # quoted in this comment, because the scan below reads this file
            # too and a quoted command position is a hit like any other.
            scan() {
              local status=0
              grep -rnE \
                '^[[:space:]]*!?[[:space:]]*compgen\b|\$\(!?[[:space:]]*compgen\b|(if|while|until|then|else|do|;|&&|\|\|)[[:space:]]+!?[[:space:]]*compgen\b' \
                "$@" || status=$?
              # 1 is "matched nothing"; 2 and up mean grep could not read a path
              # it was given, and an empty result from that is indistinguishable
              # from a clean tree. Reachable without anything being broken:
              # lib.fileset.toSource materializes a directory only when a file
              # in it matches, so ${"\${sources}"}/tests exists only while tests/ still
              # holds a .sh file. Returned rather than reported, so the callers
              # abort: hits=$(scan ...) fails the assignment under errexit, and
              # the planted count fails through pipefail.
              [ "$status" -le 1 ] || return "$status"
            }

            planted="$PWD/planted"
            mkdir -p "$planted"
            # Assembled rather than written out, so this file is not a hit in its
            # own scan and does not have to exclude itself from it. Both
            # spellings, and counted: a fixture for one of them proves only the
            # alternative it happens to take, which is how the negated form went
            # unscanned while the self-test stayed green.
            printf 'if %s -A function; then :; fi\n' compgen >"$planted/plain.sh"
            printf 'if ! %s -A function; then :; fi\n' compgen >"$planted/negated.sh"
            planted_hits=$(scan "$planted" | wc -l)
            if [ "$planted_hits" -ne 2 ]; then
              echo "build-time-shell: the scan reports $planted_hits of 2 planted usages, so the tree scan below would pass regardless" >&2
              exit 1
            fi

            hits=$(scan ${sources}/modules ${sources}/packages ${sources}/tests)
            if [ -n "$hits" ]; then
              printf '%s\n' "$hits" >&2
              echo "build-time-shell: compgen needs programmable completion, which the bash a runCommand builder runs is built without; use declare -F or a nullglob array" >&2
              exit 1
            fi
            echo "no programmable-completion builtins in build-time shell text" >"$out"
          '';
    };
}
