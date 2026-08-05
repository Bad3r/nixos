/*
  Check: site installers built by packages/firefoxpwa-site-installer exclude
  one another.

  firefoxpwa rewrites the whole of config.json through File::create with no
  lock, so two site installers that overlap lose one another's sites. Unit
  ordering cannot prevent it: Home Manager activates sd-switch before the
  sops-nix step, so a switch starts one unit and then restarts another through
  PartOf while the first is still installing, which is the direction an After=
  on either unit does not constrain. The builder therefore takes the lock for
  every installer it produces.

  Proved on the builder rather than on the installers, because the property is
  the builder's: naming any two of today's installers would have to be rewritten
  the moment a third is added, and would say nothing about that third one. Two
  installers built here through the builder must serialize; the same pair built
  with writeShellApplication directly must not, which is what shows the
  assertion can fail.
*/
_: {
  perSystem =
    { pkgs, ... }:
    let
      dataDir = "firefoxpwa-site-lock-check/data";

      # Read, pause, write: the shape of what firefoxpwa does to config.json,
      # so two runs that overlap here interleave the way they interleave there
      # and the counter ends at 1 instead of 2.
      body = ''
        n=$(cat "$data_dir/counter")
        sleep 1
        printf '%s' "$((n + 1))" >"$data_dir/counter"
      '';

      locked =
        name:
        (pkgs.callPackage ../../../packages/firefoxpwa-site-installer { }) {
          inherit name dataDir;
          xdgDataHome = "firefoxpwa-site-lock-check/xdg";
          text = body;
        };

      # The control. Same body, same directory, no builder, so the only
      # difference between the two runs below is the lock.
      unlocked =
        name:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            data_dir=${dataDir}
          ''
          + body;
        };
    in
    {
      checks."browsers/firefoxpwa-site-lock" =
        pkgs.runCommand "firefoxpwa-site-lock-check"
          {
            # Opts this check into the runtime build step in
            # .github/workflows/check.yml, which otherwise only forces drvPaths.
            passthru.runtimeCheck = true;
            nativeBuildInputs = [ pkgs.coreutils ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            data_dir=${dataDir}
            failures=0

            # Two distinct derivations, not one run twice: a lock the builder
            # took per-installer rather than on the shared directory would pass
            # a single-installer test and still let two installers overlap.
            run_pair() {
              rm -rf "$data_dir"
              install -d -m 700 "$data_dir"
              printf '0' >"$data_dir/counter"
              "$1" &
              local first=$!
              "$2" &
              local second=$!
              wait "$first"
              wait "$second"
              cat "$data_dir/counter"
            }

            got=$(run_pair ${pkgs.lib.getExe (locked "site-lock-a")} ${pkgs.lib.getExe (locked "site-lock-b")})
            if [ "$got" = 2 ]; then
              echo "PASS  two installers from the builder serialize (counter=$got)"
            else
              echo "FAIL  two installers from the builder interleaved (counter=$got, expected 2)"
              failures=$((failures + 1))
            fi

            got=$(run_pair ${pkgs.lib.getExe (unlocked "site-lock-unlocked-a")} ${pkgs.lib.getExe (unlocked "site-lock-unlocked-b")})
            if [ "$got" = 1 ]; then
              echo "PASS  the same pair without the builder loses an update (counter=$got)"
            else
              echo "FAIL  the unlocked control did not interleave (counter=$got, expected 1); this check cannot tell a working lock from a missing one" >&2
              failures=$((failures + 1))
            fi

            echo
            if [ "$failures" -ne 0 ]; then
              echo "$failures assertion(s) failed"
              exit 1
            fi
            echo "site installers built by the shared builder exclude one another" >"$out"
          '';
    };
}
