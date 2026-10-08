/*
  Check: Microsoft 365 installer behaviour (packages/firefoxpwa-m365-install).

  The installer is a shell script whose interesting branches only appear after
  firefoxpwa has rewritten config.json, which parsing and shellcheck cannot
  see. This builds the real derivation against a stub firefoxpwa and drives it
  through the states that matter for a multi-entry install:

  - the url crate normalizes what it stores (a bare origin comes back with a
    path), so any check comparing a declared URL against a value read back from
    config.json is wrong,
  - site update accepts neither --document-url nor --manifest-url, so those
    fields are immutable and a moved entry must be refused rather than patched,
  - one entry that cannot be installed must not cost the others theirs.

  The stub is passed as the firefoxpwa package rather than placed on PATH:
  writeShellApplication prepends runtimeInputs, so a PATH stub would be
  shadowed by the real binary.
*/
{
  lib,
  ...
}:
let
  catalog = import ./_m365-apps.nix;
  catalogKeys = map (app: app.key) catalog;
  catalogNames = map (app: app.name) catalog;
in
# The shipped catalog is a default no host has to restate, so nothing else
# would notice these until a site was installed under a colliding record.
assert lib.assertMsg (
  lib.unique catalogKeys == catalogKeys
) "browsers/firefoxpwa-m365: _m365-apps.nix has duplicate keys";
assert lib.assertMsg (
  lib.unique catalogNames == catalogNames
) "browsers/firefoxpwa-m365: _m365-apps.nix has duplicate names";
assert lib.assertMsg (lib.all (
  app: lib.hasPrefix "https://" app.url
) catalog) "browsers/firefoxpwa-m365: every _m365-apps.nix start URL must be https";
# The catalog is the option's default, and an option's type is checked only
# when its value is forced: ./m365.nix reaches apps behind `m365Enabled &&`,
# no host sets that, and ./module-check.nix passes osConfig as a plain attrset,
# so nothing anywhere applies the key's strMatching to these entries. Restated
# rather than read back from the option because reaching the type needs a NixOS
# evaluation this file does not do; a widened alphabet fails here loudly, which
# is the safe direction for the drift.
assert lib.assertMsg (lib.all (app: builtins.match "[a-z0-9][a-z0-9-]*" app.key != null)
  catalog
) "browsers/firefoxpwa-m365: every _m365-apps.nix key must match the option's path-safe alphabet";
{
  perSystem =
    { pkgs, ... }:
    let
      stub = pkgs.writeShellApplication {
        name = "firefoxpwa";
        runtimeInputs = [
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          # Resolved the way the real binary does (native/src/directories.rs):
          # FFPWA_USERDATA if set, else the XDG data directory plus a firefoxpwa
          # suffix. The stub must not be told the path directly, or it would
          # agree with an installer that picked its own and hide the mismatch.
          userdata="''${FFPWA_USERDATA:-''${XDG_DATA_HOME:-$HOME/.local/share}/firefoxpwa}"
          mkdir -p "$userdata"
          # Recorded so a check can assert this equals the xdgDataHome the
          # installer was given, proving it pins system integration's directory
          # from that parameter rather than from the caller's environment.
          printf '%s' "$XDG_DATA_HOME" >"$userdata/.xdg-data-home-seen"
          config_file="$userdata/config.json"
          [ -f "$config_file" ] || echo '{"sites":{}}' >"$config_file"

          # The url crate fills in an empty path, so a bare origin is stored
          # with a trailing slash. The stub only has to be wrong in the same
          # way the real one is.
          normalize() {
            if [[ $1 =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]+$ ]]; then
              printf '%s/' "$1"
            else
              printf '%s' "$1"
            fi
          }

          [ "''${1:-}" = "site" ] || exit 64

          case "''${2:-}" in
            install)
              manifest_url="$3"
              start_url="" document_url="" name=""
              while [ $# -gt 0 ]; do
                case "$1" in
                  --start-url) start_url="$2" ;;
                  --document-url) document_url="$2" ;;
                  --name) name="$2" ;;
                esac
                shift
              done
              # Reproduces an install that fails before storage.write ever
              # runs, for example a network error: the site is never
              # registered, unlike STUB_FAIL_AFTER_REGISTER.
              if [ "''${STUB_FAIL_NAME:-}" = "$name" ] && [ -n "''${STUB_FAIL_BEFORE_REGISTER:-}" ]; then
                exit 1
              fi
              # Allocated from a counter rather than the site count, so several
              # can coexist, a check can tell one entry's site from another's,
              # and an id is never handed out twice: a real ulid is unique for
              # the life of the profile, while a count reuses the id of a site
              # that was uninstalled and would silently overwrite its successor.
              seq_file="$userdata/.stub-ulid-seq"
              seq=0
              [ ! -f "$seq_file" ] || seq=$(<"$seq_file")
              ulid="01STUB$seq"
              printf '%s' "$((seq + 1))" >"$seq_file"
              # Decoded from the manifest the installer actually built, the way
              # ./dmail-check.nix's stub does. Taking it from --document-url
              # would make manifest.scope a copy of a field the installer passes
              # separately, so the scope assertion could not see a manifest built
              # with the wrong one, which is the invariant the whole design rests
              # on: scope is fixed at install time and must be the bare origin.
              scope=$(printf '%s' "''${manifest_url#*base64,}" | base64 -d | jq -r .scope)
              jq --arg u "$ulid" --arg n "$name" --arg m "$manifest_url" \
                --arg s "$(normalize "$start_url")" --arg d "$(normalize "$document_url")" \
                --arg sc "$(normalize "$scope")" \
                '.sites[$u] = {
                   config: {name: $n, start_url: $s, document_url: $d, manifest_url: $m},
                   manifest: {scope: $sc}
                 }' "$config_file" >"$config_file.next"
              mv "$config_file.next" "$config_file"
              # Reproduces an install that registers the site and then fails,
              # for example on desktop integration.
              if [ "''${STUB_FAIL_NAME:-}" = "$name" ] && [ -n "''${STUB_FAIL_AFTER_REGISTER:-}" ]; then
                exit 1
              fi
              ;;
            update)
              ulid="$3"
              # Reproduces an update that fails without touching the site, the
              # one failure the installer counts as a refusal rather than a
              # fault, and the repair every other branch defers to.
              [ -z "''${STUB_FAIL_UPDATE:-}" ] || exit 1
              start_url=""
              while [ $# -gt 0 ]; do
                case "$1" in
                  # The real binary takes neither: accepting them here would
                  # hide an installer trying to rewrite an immutable field.
                  --document-url | --manifest-url) exit 64 ;;
                  --start-url) start_url="$2" ;;
                esac
                shift
              done
              jq -e --arg u "$ulid" '.sites[$u]' "$config_file" >/dev/null
              jq --arg u "$ulid" --arg s "$(normalize "$start_url")" \
                '.sites[$u].config.start_url = $s' "$config_file" >"$config_file.next"
              mv "$config_file.next" "$config_file"
              ;;
            *) exit 64 ;;
          esac
        '';
      };

      # Deliberately not $XDG_DATA_HOME/firefoxpwa: passing a directory the
      # script could not have guessed proves it uses the parameter rather than
      # re-deriving a path of its own. Relative, so it lands in the build
      # directory rather than a fixed path two concurrent builds would share.
      dataDir = "firefoxpwa-m365-check/data";
      # A third, distinct path: the build environment's own XDG_DATA_HOME (set
      # below) is deliberately wrong, so asserting the stub sees this value
      # proves the installer's own export takes effect.
      pinnedXdgDataHome = "firefoxpwa-m365-check/xdg-pinned";

      mkInstaller =
        apps:
        (pkgs.callPackage ../../../packages/firefoxpwa-m365-install { }) {
          firefoxpwa = stub;
          xdgDataHome = pinnedXdgDataHome;
          inherit dataDir apps;
          # Exercises the retry loop's control flow without three real
          # 5-second sleeps per entry.
          retryDelay = 0;
        };
      inherit (mkInstaller [ ]) refusalExitStatus;

      declared = mkInstaller [
        {
          key = "alpha";
          name = "Alpha";
          url = "https://alpha.example/";
        }
        {
          key = "beta";
          name = "Beta";
          url = "https://beta.example/";
        }
      ];
      # Alpha moved within its own origin: applied in place.
      moved = mkInstaller [
        {
          key = "alpha";
          name = "Alpha";
          url = "https://alpha.example/deep/link";
        }
        {
          key = "beta";
          name = "Beta";
          url = "https://beta.example/";
        }
      ];
      # Alpha installed straight at a deep URL rather than moved there. The
      # discriminating case for scope: a start URL equal to its own origin
      # normalizes to the same string either way, so only an entry installed
      # below its origin can show whether the manifest carries the origin or the
      # start URL.
      deep = mkInstaller [
        {
          key = "alpha";
          name = "Alpha";
          url = "https://alpha.example/deep/link";
        }
      ];
      # Alpha moved to another origin: refused, because scope is immutable.
      crossOrigin = mkInstaller [
        {
          key = "alpha";
          name = "Alpha";
          url = "https://alpha.example.net/";
        }
        {
          key = "beta";
          name = "Beta";
          url = "https://beta.example/";
        }
      ];
      # The shipped default, built and driven like any other list: writing it
      # is the only thing that proves the catalog survives escapeShellArg,
      # shellcheck and a real run, since no host enables the toggle yet.
      shipped = mkInstaller catalog;
      # Alpha's key edited while its name stays: the lookup still finds the
      # site, but every record moved to the new slug, so nothing can show the
      # site is still at the origin it was installed at.
      rekeyed = mkInstaller [
        {
          key = "alpha-2";
          name = "Alpha";
          url = "https://alpha.example/";
        }
        {
          key = "beta";
          name = "Beta";
          url = "https://beta.example/";
        }
      ];
      # Alpha's launcher name edited while its key stays: the lookup misses the
      # site the key installed, so the fresh-install branch has to refuse rather
      # than register a second one.
      renamed = mkInstaller [
        {
          key = "alpha";
          name = "Alpha Renamed";
          url = "https://alpha.example/";
        }
        {
          key = "beta";
          name = "Beta";
          url = "https://beta.example/";
        }
      ];
      credentials = mkInstaller [
        {
          key = "alpha";
          name = "Alpha";
          url = "https://user:pass@alpha.example/";
        }
        {
          key = "beta";
          name = "Beta";
          url = "https://beta.example/";
        }
      ];
    in
    {
      checks."browsers/firefoxpwa-m365" =
        pkgs.runCommand "firefoxpwa-m365-check"
          {
            # Opts this check into the build step in .github/workflows/check.yml;
            # its assertions run in the derivation, so forcing drvPath proves
            # nothing. passthru, not a plain attr: runCommand's second argument
            # becomes derivationArgs, so a plain attr would be an unread build
            # environment variable and part of the derivation hash.
            passthru.runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.jq
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
            ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            export HOME="$PWD/home"
            # Points somewhere the installer must not use: it pins both
            # FFPWA_USERDATA and XDG_DATA_HOME itself.
            export XDG_DATA_HOME="$PWD/xdg"
            data_dir=${lib.escapeShellArg dataDir}
            pinned_xdg_data_home=${lib.escapeShellArg pinnedXdgDataHome}
            config_file="$data_dir/config.json"
            install -d "$HOME" "$XDG_DATA_HOME"

            declared=${lib.getExe declared}
            shipped=${lib.getExe shipped}
            moved=${lib.getExe moved}
            cross_origin=${lib.getExe crossOrigin}
            renamed=${lib.getExe renamed}
            deep=${lib.getExe deep}
            rekeyed=${lib.getExe rekeyed}
            credentials=${lib.getExe credentials}
            failures=0

            reset() {
              rm -rf "$data_dir" "$pinned_xdg_data_home"
              install -d -m 700 "$data_dir"
            }

            # Matched with case, not piped into grep: under pipefail, grep -q
            # exiting on first match can SIGPIPE the producer and flip a real
            # match into a reported failure.
            #
            # A matching fragment with the wrong status leaves the case arm, and
            # so the case, returning 1, which does not trip errexit: bash
            # ignores -e for the left side of an && list and the enclosing
            # compound inherits that, so the FAIL branch below still reports the
            # mismatch and the assertions after it still run.
            expect() {
              local label="$1" installer="$2" want_rc="$3" want_text="$4" out rc=0 ok=1
              out=$("$installer" 2>&1) || rc=$?
              case "$out" in
                *"$want_text"*) [ "$rc" = "$want_rc" ] && ok=0 ;;
              esac
              if [ "$ok" = 0 ]; then
                echo "PASS  $label"
              else
                echo "FAIL  $label (rc=$rc, expected $want_rc; wanted output containing '$want_text')"
                printf '%s\n' "$out" | sed 's/^/      /'
                failures=$((failures + 1))
              fi
            }

            # A rerun that changed nothing prints nothing, so silence is the
            # observable. expect with an empty fragment pins only the exit
            # status, which a run that calls site update on every entry also
            # satisfies: without the installer's no-op fast path the rerun still
            # exits 0 with the same site count, and every other assertion in
            # this check requires "refreshing start URL" rather than forbidding
            # it, so nothing would notice.
            expect_silent() {
                local label="$1" installer="$2" out rc=0
                out=$("$installer" 2>&1) || rc=$?
                if [ "$rc" = 0 ] && [ -z "$out" ]; then
                  echo "PASS  $label"
                else
                  echo "FAIL  $label (rc=$rc, expected 0 and no output)"
                  printf '%s\n' "$out" | sed 's/^/      /'
                  failures=$((failures + 1))
                fi
            }

            assert_equal() {
              if [ "$2" = "$3" ]; then
                echo "PASS  $1"
              else
                echo "FAIL  $1: got '$2', expected '$3'"
                failures=$((failures + 1))
              fi
            }

            site_count() { jq -r '(.sites // {}) | length' "$config_file"; }
            start_url_of() {
              jq -r --arg n "$1" \
                'first((.sites // {}) | to_entries[] | select(.value.config.name == $n) | .value.config.start_url) // ""' \
                "$config_file"
            }
            scope_of() {
              jq -r --arg n "$1" \
                'first((.sites // {}) | to_entries[] | select(.value.config.name == $n) | .value.manifest.scope) // ""' \
                "$config_file"
            }

            echo "-- a fresh run installs every declared entry --"
            reset
            expect "fresh install" "$declared" 0 "installed 'Alpha'"
            assert_equal "both sites registered" "$(site_count)" 2
            assert_equal "alpha start URL stored normalized" "$(start_url_of Alpha)" "https://alpha.example/"
            assert_equal "alpha scope is the bare origin" "$(scope_of Alpha)" "https://alpha.example/"
            assert_equal "alpha applied record is the declared URL" \
              "$(cat "$data_dir/m365-alpha-applied-url")" "https://alpha.example/"
            assert_equal "alpha origin recorded" \
              "$(cat "$data_dir/m365-alpha-applied-origin")" "https://alpha.example"
            assert_equal "alpha ulid recorded" "$(cat "$data_dir/m365-alpha-applied-ulid")" "01STUB0"
            if [ -e "$data_dir/m365-alpha-installing" ]; then
              echo "FAIL  pending record left behind after a successful install"
              failures=$((failures + 1))
            else
              echo "PASS  pending record cleared after a successful install"
            fi

            echo
            echo "-- an entry installed below its origin still scopes to the origin --"
            reset
            expect "deep install" "$deep" 0 "installed 'Alpha'"
            # Scope is fixed at install time and site update cannot rewrite it,
            # so a manifest built from the start URL rather than the origin
            # would push every same-origin navigation into the external browser.
            assert_equal "scope is the origin, not the start URL" \
              "$(scope_of Alpha)" "https://alpha.example/"
            assert_equal "the start URL is still the declared one" \
              "$(start_url_of Alpha)" "https://alpha.example/deep/link"
            reset
            "$declared" >/dev/null

            echo
            echo "-- rerunning the same generation changes nothing --"
            expect_silent "idempotent rerun" "$declared"
            assert_equal "no duplicate sites" "$(site_count)" 2

            echo
            echo "-- an entry moved within its origin is applied in place --"
            expect "same-origin move" "$moved" 0 "refreshing start URL for 'Alpha'"
            assert_equal "still no duplicate sites" "$(site_count)" 2
            assert_equal "alpha start URL updated" "$(start_url_of Alpha)" "https://alpha.example/deep/link"
            assert_equal "alpha applied record updated" \
              "$(cat "$data_dir/m365-alpha-applied-url")" "https://alpha.example/deep/link"
            # A failed update must leave the applied record where it was: the
            # record is what the no-op fast path compares against, so advancing
            # it here would make the next run agree the URL is already applied
            # and never retry. The move back below is that retry.
            export STUB_FAIL_UPDATE=1
            expect "failed update refused" "$declared" 1 "failed to update start URL for 'Alpha'"
            unset STUB_FAIL_UPDATE
            assert_equal "alpha applied record not advanced past a failed update" \
              "$(cat "$data_dir/m365-alpha-applied-url")" "https://alpha.example/deep/link"
            assert_equal "alpha start URL untouched by a failed update" \
              "$(start_url_of Alpha)" "https://alpha.example/deep/link"
            # The declared URL is a bare origin while config.json holds the
            # url crate's trailing-slash form, so a no-op here would mean the
            # installer compared against config.json instead of its record.
            expect "move back to the origin" "$declared" 0 "refreshing start URL for 'Alpha'"
            assert_equal "alpha start URL restored" "$(start_url_of Alpha)" "https://alpha.example/"

            echo
            echo "-- an entry moved across origins is refused, the rest are not --"
            expect "cross-origin move" "$cross_origin" ${toString refusalExitStatus} "uninstall the site so this unit can reinstall it at the new origin"
            assert_equal "no site added for the new origin" "$(site_count)" 2
            assert_equal "alpha still points at the installed origin" \
              "$(start_url_of Alpha)" "https://alpha.example/"
            assert_equal "beta record untouched" \
              "$(cat "$data_dir/m365-beta-applied-url")" "https://beta.example/"

            echo
            echo "-- renaming an entry is refused rather than orphaning its site --"
            reset
            "$declared" >/dev/null
            expect "rename refused" "$renamed" ${toString refusalExitStatus} "is a new name for the site this unit installed"
            assert_equal "no second site registered under the new name" "$(site_count)" 2
            assert_equal "the ulid record still names the original site" \
              "$(cat "$data_dir/m365-alpha-applied-ulid")" "01STUB0"
            assert_equal "the applied record still names the original entry" \
              "$(cat "$data_dir/m365-alpha-applied-url")" "https://alpha.example/"
            # config.json gone entirely rather than the site removed from it:
            # the rename guard reads that file, so it has to tell "no file" from
            # "cannot read this file" and let the first install.
            rm -f "$config_file"
            expect "a config.json that is gone does not block the install" "$renamed" 0 "installed 'Alpha Renamed'"
            # 01STUB2, not 01STUB0: only config.json was removed, so the stub's
            # ulid counter survives and the reinstall is a genuinely new site.
            assert_equal "alpha ulid re-recorded" "$(cat "$data_dir/m365-alpha-applied-ulid")" "01STUB2"

            reset
            "$declared" >/dev/null
            expect "rename still refused after the reset" "$renamed" ${toString refusalExitStatus} "is a new name for the site this unit installed"
            # An uninstall leaves the same stale record but takes the site, and
            # that case must still reinstall: the guard is on the site being
            # there, not on the record existing.
            jq 'del(.sites["01STUB0"])' "$config_file" >"$config_file.next"
            mv "$config_file.next" "$config_file"
            expect "an uninstalled site is reinstalled under the new name" "$renamed" 0 "installed 'Alpha Renamed'"

            echo
            echo "-- editing an entry's key is refused, not silently reinstalled --"
            reset
            "$declared" >/dev/null
            # Documented on the option as destructive: the remedy the message
            # names destroys a working PWA profile, so what must not happen is
            # the installer deciding that for itself.
            expect "key edit refused" "$rekeyed" ${toString refusalExitStatus} "nothing records the origin it was installed at"
            assert_equal "no site added under the new slug" "$(site_count)" 2
            assert_equal "the old slug's records are left for the user to clear" \
              "$(cat "$data_dir/m365-alpha-applied-ulid")" "01STUB0"
            if [ -e "$data_dir/m365-alpha-2-applied-ulid" ]; then
              echo "FAIL  a record was written under the new slug for a refused entry"
              failures=$((failures + 1))
            else
              echo "PASS  nothing recorded under the new slug"
            fi

            echo
            echo "-- a start URL with credentials is refused before any site lookup --"
            reset
            expect "credentials refused" "$credentials" ${toString refusalExitStatus} "embeds credentials"
            assert_equal "only the other entry was installed" "$(site_count)" 1
            assert_equal "beta installed anyway" "$(cat "$data_dir/m365-beta-applied-url")" "https://beta.example/"
            # A retryable fault must outrank a permanent refusal: the refusal
            # is a successful exit for the user service, so the wrong
            # precedence would leave the transient fault with no rerun.
            reset
            export STUB_FAIL_NAME=Beta STUB_FAIL_BEFORE_REGISTER=1
            expect "a retryable fault outranks a permanent refusal" "$credentials" 1 "failed after 3 attempts"
            unset STUB_FAIL_NAME STUB_FAIL_BEFORE_REGISTER

            echo
            echo "-- a same-named site this unit did not install is refused --"
            reset
            "$declared" >/dev/null
            # What an uninstall followed by a browser-extension install leaves:
            # the site carries the managed name but not the manifest URL this
            # installer would have given it, and its ulid record is gone.
            rm -f "$data_dir/m365-alpha-applied-ulid"
            jq '.sites["01STUB0"].config.manifest_url = "https://alpha.example/manifest.json"' \
              "$config_file" >"$config_file.next"
            mv "$config_file.next" "$config_file"
            expect "foreign site refused" "$declared" ${toString refusalExitStatus} "is not the site this unit installed"
            assert_equal "no second Alpha registered" "$(site_count)" 2

            echo
            echo "-- a truncated config.json is retryable rather than a second install --"
            reset
            "$declared" >/dev/null
            : >"$config_file"
            expect "zero-byte config.json is retryable" "$declared" 1 "not installing a second"

            echo
            echo "-- an entry that never registers does not stop the others --"
            reset
            # Exported rather than prefixed onto the call: the stub reads them
            # from its environment, and a prefix on a shell function is not
            # reliably scoped to that call.
            export STUB_FAIL_NAME=Alpha STUB_FAIL_BEFORE_REGISTER=1
            expect "failing entry reported" "$declared" 1 "failed after 3 attempts"
            unset STUB_FAIL_NAME STUB_FAIL_BEFORE_REGISTER
            assert_equal "the other entry installed" "$(site_count)" 1
            assert_equal "beta installed" "$(cat "$data_dir/m365-beta-applied-url")" "https://beta.example/"
            for record in applied-url applied-origin applied-ulid installing; do
              if [ -e "$data_dir/m365-alpha-$record" ]; then
                echo "FAIL  m365-alpha-$record survived an install that registered nothing"
                failures=$((failures + 1))
              else
                echo "PASS  m365-alpha-$record cleared"
              fi
            done

            echo
            echo "-- an install that registers the site and then fails is repaired, not duplicated --"
            reset
            export STUB_FAIL_NAME=Alpha STUB_FAIL_AFTER_REGISTER=1
            expect "registered-then-failed reported" "$declared" 1 "was registered by a failed install"
            unset STUB_FAIL_NAME STUB_FAIL_AFTER_REGISTER
            assert_equal "exactly one Alpha registered" "$(site_count)" 2
            expect "next run repairs it" "$declared" 0 "refreshing start URL for 'Alpha'"
            assert_equal "still exactly one Alpha" "$(site_count)" 2
            assert_equal "alpha applied record recovered" \
              "$(cat "$data_dir/m365-alpha-applied-url")" "https://alpha.example/"

            echo
            echo "-- a record write that fails stops the run instead of reporting an install --"
            reset
            # A directory where the record's temporary goes: the redirection
            # fails, which is what a full or read-only filesystem does to this
            # write, without needing either. Planted on the ulid record because
            # that is the write whose silent failure is unrecoverable: the
            # pending record is removed on the next line, and without either
            # record every later run refuses the entry as foreign.
            mkdir -p "$data_dir/m365-alpha-applied-ulid.next"
            # Aborts rather than counting a refusal: a failed record is a
            # filesystem fault, not a state this installer decided not to act
            # on. Asserting the message text would only prove bash still names
            # the file it could not open; what has to hold is that the run
            # stopped and left the entry repairable.
            expect "failed record write is fatal" "$declared" 1 "m365-alpha-applied-ulid.next"
            assert_equal "the entry after the fault was never attempted" "$(site_count)" 1
            if [ -s "$data_dir/m365-alpha-installing" ]; then
              echo "PASS  pending record survives a failed ulid write"
            else
              echo "FAIL  pending record cleared despite the failed ulid write"
              failures=$((failures + 1))
            fi
            rmdir "$data_dir/m365-alpha-applied-ulid.next"
            # The pending record is the whole point of the assertion above: it
            # is what lets the adopt branch recognize the registered site as
            # this unit's own instead of refusing it forever.
            expect "the next run adopts the site the fault left behind" "$declared" 0 "installed 'Beta'"
            assert_equal "no second Alpha registered" "$(site_count)" 2
            assert_equal "alpha ulid recorded on the recovery run" \
              "$(cat "$data_dir/m365-alpha-applied-ulid")" "01STUB0"

            echo
            echo "-- the shipped catalog installs end to end --"
            reset
            expect "catalog install" "$shipped" 0 "installed 'Word'"
            assert_equal "every catalog entry installed" \
              "$(site_count)" ${toString (builtins.length catalog)}
            expect_silent "catalog rerun" "$shipped"
            assert_equal "catalog rerun adds nothing" \
              "$(site_count)" ${toString (builtins.length catalog)}

            echo
            echo "-- the installer is built through the shared site installer --"
            # ./site-lock-check.nix proves the builder serializes, but nothing
            # there names this derivation: rewriting default.nix back to a
            # direct writeShellApplication would keep that check green while
            # losing the mutual exclusion it exists to provide. The lock path is
            # the tie, since it is the shared resource rather than the mechanism.
            if grep -q '\.config-lock' "$declared"; then
              echo "PASS  takes the shared site lock"
            else
              echo "FAIL  no shared site lock in the installer text; it was not built through packages/firefoxpwa-site-installer"
              failures=$((failures + 1))
            fi

            echo
            echo "-- the installer uses the directories it is given --"
            assert_equal "system integration directory pinned" \
              "$(cat "$data_dir/.xdg-data-home-seen")" "$pinned_xdg_data_home"
            if [ -e "$XDG_DATA_HOME/firefoxpwa" ]; then
              echo "FAIL  installer re-derived a path under XDG_DATA_HOME"
              failures=$((failures + 1))
            else
              echo "PASS  nothing written outside the configured data directory"
            fi
            # Globbed rather than matched with compgen: the bash a runCommand
            # builder runs is built without programmable completion, so the
            # first form of this assertion reported "command not found" into
            # the else branch and passed on every run. Planted against a real
            # temporary first, because an assertion nothing proves can fail is
            # what made that defect invisible.
            leftover_temps() {
              local found=()
              shopt -s nullglob
              found=("$data_dir"/*.next)
              shopt -u nullglob
              printf '%s\n' "''${found[@]##*/}"
            }
            : >"$data_dir/planted.next"
            assert_equal "leftover detector reports a planted temporary" \
              "$(leftover_temps)" "planted.next"
            rm -f "$data_dir/planted.next"
            assert_equal "record writes leave no temporary" "$(leftover_temps)" ""

            echo
            echo "-- the installer creates the data directory it is given --"
            # reset pre-creates the directory for every other scenario, so this
            # is the first-run path that proves the shared builder owns it.
            rm -rf "$data_dir" "$pinned_xdg_data_home"
            expect "install into a missing data directory" "$declared" 0 "installed 'Alpha'"
            assert_equal "the data directory is created 0700" \
              "$(stat -c %a "$data_dir")" 700

            echo
            if [ "$failures" -ne 0 ]; then
              echo "$failures assertion(s) failed"
              exit 1
            fi
            echo "all assertions passed" >"$out"
          '';
    };
}
