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

            scan() {
              grep -rnE \
                '^[[:space:]]*compgen\b|\$\(compgen\b|(if|while|until|then|else|do|;|&&|\|\|)[[:space:]]+compgen\b' \
                "$@" || true
            }

            planted="$PWD/planted"
            mkdir -p "$planted"
            # Assembled rather than written out, so this file is not a hit in its
            # own scan and does not have to exclude itself from it.
            printf 'if %s -A function; then :; fi\n' compgen >"$planted/fixture.sh"
            if [ -z "$(scan "$planted")" ]; then
              echo "build-time-shell: the scan reports nothing for a planted usage, so the tree scan below would pass regardless" >&2
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
