/*
  Check: DMail installer behaviour (packages/firefoxpwa-dmail-install).

  The installer is a shell script with seven outcomes, and several of its
  branches guard states that only appear after firefoxpwa has rewritten
  config.json. Parsing and shellcheck cannot see any of that, so this builds the
  real derivation against a stub firefoxpwa and drives the script through the
  states that have actually regressed:

  - the url crate normalizes what it stores (default port dropped, IDN
    punycoded, empty path filled in, host and scheme lowercased), so any check
    comparing a raw secret against a value read back from config.json is wrong,
  - site update accepts neither --document-url nor --manifest-url, so those
    fields are immutable and must never receive the rotating secret,
  - an install can register the site and still fail, which must not be recorded
    as applied.

  The stub is passed as the firefoxpwa package rather than placed on PATH:
  writeShellApplication prepends runtimeInputs, so a PATH stub would be shadowed
  by the real binary.
*/
{
  lib,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      idnHost = "mail.exämple.com";
      idnPunycode = "mail.xn--exmple-cua.com";

      # Emulates the parts of the url crate's serialization that the installer
      # has to stay clear of. Not a URL parser: it only has to be wrong in the
      # same ways the real one is.
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
          # Recorded on every invocation: a check can assert this equals the
          # xdgDataHome the installer was given, proving it pins system
          # integration's directory from that parameter rather than from
          # whatever XDG_DATA_HOME the caller's environment happens to hold.
          printf '%s' "$XDG_DATA_HOME" >"$userdata/.xdg-data-home-seen"
          config_file="$userdata/config.json"
          [ -f "$config_file" ] || echo '{"sites":{}}' >"$config_file"

          normalize() {
            local url="$1" scheme rest authority userinfo host tail
            scheme="''${url%%://*}"
            rest="''${url#*://}"
            authority="''${rest%%[/?#]*}"
            tail="''${rest#"$authority"}"
            scheme="''${scheme,,}"
            # Userinfo sits before @ in the authority and the real url crate
            # preserves its case, lowercasing only the host. Splitting it off
            # before ''${host,,} keeps the stub honest about that: folding the
            # whole authority would hide a leak the installer stops passing on.
            case "$authority" in
              *@*)
                userinfo="''${authority%%@*}@"
                host="''${authority#*@}"
                ;;
              *)
                userinfo=""
                host="$authority"
                ;;
            esac
            host="''${host,,}"
            case "$scheme:$host" in
              https:*:443) host="''${host%:443}" ;;
              http:*:80) host="''${host%:80}" ;;
            esac
            host="''${host/${idnHost}/${idnPunycode}}"
            [ -n "$tail" ] || tail="/"
            printf '%s://%s%s%s' "$scheme" "$userinfo" "$host" "$tail"
          }

          write_site() {
            jq --arg n "$3" --arg s "$(normalize "$2")" --arg d "$(normalize "$4")" \
              --arg m "$1" --arg sc "$(normalize "$5")" \
              '.sites["01STUB"] = {
                 config: {name: $n, start_url: $s, document_url: $d, manifest_url: $m},
                 manifest: {scope: $sc}
               }' "$config_file" >"$config_file.next"
            mv "$config_file.next" "$config_file"
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
              # runs, for example a network error fetching the manifest: the
              # site is never registered, unlike STUB_FAIL_AFTER_REGISTER.
              [ -z "''${STUB_FAIL_BEFORE_REGISTER:-}" ] || exit 1
              # Recorded at the same point storage.write runs in the real
              # binary, before this stub's own write below: a check can then
              # assert default.nix's pending_file already holds this exact
              # manifest_url here, the instant registration happens, rather
              # than only after this call returns, and rather than an empty
              # marker the adopt check's content match would then always
              # refuse for a genuine repair. A kill exactly here, between
              # this line and the real storage.write, is the window c30d6ce's
              # marker exists to cover.
              if [ -e "$userdata/dmail-installing" ] \
                && [ "$(cat "$userdata/dmail-installing")" = "$manifest_url" ]; then
                echo match >"$userdata/.pending-file-at-register"
              else
                echo mismatch >"$userdata/.pending-file-at-register"
              fi
              scope=$(printf '%s' "''${manifest_url#*base64,}" | base64 -d | jq -r .scope)
              # Reproduces firefoxpwa reporting success while storage.write
              # never lands, for example a write racing firefoxpwa
              # connector's own use of config.json: site_ulid then finds
              # nothing under $app_name despite the 0 exit, unlike
              # STUB_FAIL_BEFORE_REGISTER, which reports failure.
              [ -n "''${STUB_LOSE_REGISTRATION:-}" ] || write_site "$manifest_url" "$start_url" "$name" "$document_url" "$scope"
              # Reproduces config.json racing firefoxpwa connector's own
              # rewrite right after this call registers the site: site_ulid's
              # read of it, whether from this call's own success branch or a
              # subsequent failed-attempt branch, then fails rather than
              # finding nothing, unlike STUB_LOSE_REGISTRATION, which leaves
              # valid JSON with no site in it.
              [ -z "''${STUB_CORRUPT_AFTER_REGISTER:-}" ] || printf 'not json' >"$config_file"
              # Reproduces an install that registers the site and then fails, for
              # example when desktop integration errors after storage.write.
              [ -z "''${STUB_FAIL_AFTER_REGISTER:-}" ] || exit 1
              ;;
            update)
              ulid="$3"
              start_url=""
              while [ $# -gt 0 ]; do
                case "$1" in
                  --start-url) start_url="$2" ;;
                  # SiteUpdateCommand carries neither, so clap would reject them.
                  --document-url | --manifest-url)
                    echo "stub: unexpected argument '$1'" >&2
                    exit 2
                    ;;
                esac
                shift
              done
              # Reproduces site update itself failing, for example storage.write
              # erroring on the rewrite: config.json must stay exactly as it was.
              [ -z "''${STUB_FAIL_UPDATE:-}" ] || exit 1
              jq --arg i "$ulid" --arg s "$(normalize "$start_url")" \
                '.sites[$i].config.start_url = $s' "$config_file" >"$config_file.next"
              mv "$config_file.next" "$config_file"
              ;;
            *) exit 64 ;;
          esac
        '';
      };

      # Relative to the check's build directory. An absolute /tmp path is shared
      # mutable state once sandboxing is off: a leftover or differently-owned
      # directory fails `install -d -m 700`, parallel builds overwrite each
      # other's config.json, and the decrypted-URL stand-ins outlive the build.
      secretDir = "firefoxpwa-dmail-check";

      # Deliberately not $XDG_DATA_HOME/firefoxpwa: passing a directory the
      # script could not have guessed proves it uses the parameter rather than
      # re-deriving a path of its own.
      dataDir = "${secretDir}/data";

      # A third, distinct path: the build environment's own XDG_DATA_HOME
      # (set below) is deliberately wrong, so pinning system integration's
      # directory from this parameter instead, and asserting the stub sees
      # this value rather than the environment's, proves the installer's own
      # export takes effect rather than merely passing the ambient value
      # through unread.
      pinnedXdgDataHome = "${secretDir}/xdg-pinned";

      mkInstaller =
        appName:
        (pkgs.callPackage ../../../packages/firefoxpwa-dmail-install { }) {
          firefoxpwa = stub;
          urlPath = "${secretDir}/url";
          xdgDataHome = pinnedXdgDataHome;
          inherit dataDir appName;
          # Exercises the retry loop's control flow without three real 5-second
          # sleeps per check run.
          retryDelay = 0;
        };

      installer = mkInstaller "DMail";
      # programs.firefoxpwa.dmail.name edited on a host that already installed
      # the site: the records keep their fixed dmail-* paths, so the lookup
      # misses and nothing but the guard stops a second site being registered.
      renamed = mkInstaller "Work Mail";
    in
    {
      checks."browsers/firefoxpwa-dmail" =
        pkgs.runCommand "firefoxpwa-dmail-check"
          {
            # Opts this check into the build step in .github/workflows/check.yml.
            # Its assertions run in the derivation, so forcing drvPath proves
            # nothing; the marker keeps that opt-in at the definition site
            # instead of hardcoding a name in the workflow. passthru, not a
            # plain attr: runCommand's second argument becomes derivationArgs,
            # so a plain attr here would be a real (unread) build environment
            # variable and part of the derivation hash, rebuilding the check on
            # every CI-selection change. passthru is merged onto the
            # derivation value by lib.extendDerivation instead, which is what
            # check.yml's (builtins.getAttr n checks).runtimeCheck or false
            # reads.
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
            # FFPWA_USERDATA and XDG_DATA_HOME itself, from data_dir and
            # xdgDataHome, so anything landing under here is a re-derived
            # path rather than one this parameter set actually named.
            export XDG_DATA_HOME="$PWD/xdg"
            secret_dir=${lib.escapeShellArg secretDir}
            url_file="$secret_dir/url"
            data_dir=${lib.escapeShellArg dataDir}
            pinned_xdg_data_home=${lib.escapeShellArg pinnedXdgDataHome}
            config_file="$data_dir/config.json"
            marker="$data_dir/dmail-applied-url"
            install -d "$HOME" "$XDG_DATA_HOME" "$secret_dir"

            installer=${lib.getExe installer}
            renamed=${lib.getExe renamed}
            failures=0

            reset() {
              rm -rf "$data_dir"
              install -d -m 700 "$data_dir"
            }

            set_url() { printf '%s\n' "$1" >"$url_file"; }

            # Runs the installer and checks exit status and a message fragment.
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
              # Fourth argument, defaulting to the DMail installer: a variant
              # built with another launcher name drives the same assertions.
              local label="$1" want_rc="$2" want_text="$3" runner="''${4:-$installer}" out rc=0 ok=1
              out=$("$runner" 2>&1) || rc=$?
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

            assert_equal() {
              if [ "$2" = "$3" ]; then
                echo "PASS  $1"
              else
                echo "FAIL  $1: got '$2', expected '$3'"
                failures=$((failures + 1))
              fi
            }

            # config.json with the data: manifest expanded. The manifest is stored
            # base64-encoded in manifest_url, so a plain grep over config.json
            # cannot see a secret that leaked into it.
            decoded_manifest() {
              local manifest_url
              manifest_url=$(jq -r '.sites["01STUB"].config.manifest_url // ""' "$config_file")
              case "$manifest_url" in
                *base64,*) printf '%s' "''${manifest_url#*base64,}" | base64 -d ;;
              esac
            }

            decoded_config() {
              cat "$config_file"
              decoded_manifest
            }

            # Captured, not piped into grep: the runCommand sets pipefail, so a
            # SIGPIPE on the producer when grep -q exits early would make the if
            # read false and pass an assertion whose token is present.
            assert_absent() {
              local haystack
              haystack=$(decoded_config)
              case "$haystack" in
                *"$2"*)
                  echo "FAIL  $1: '$2' still reachable from config.json"
                  failures=$((failures + 1))
                  ;;
                *) echo "PASS  $1" ;;
              esac
            }

            echo "-- install, idempotence, same-origin rotation --"
            reset
            set_url '  https://mail.example.com '
            expect "whitespace-padded secret installs" 0 "installed 'DMail'"
            # A kill during firefoxpwa site install, after its own
            # storage.write registers the site but before this call returns,
            # is the window the pending marker exists to cover: it must
            # already hold this attempt's manifest_url by the time
            # registration happens, not only after the call returns, and not
            # as an empty marker the adopt check's content match would then
            # always refuse for a genuine repair.
            if [ "$(cat "$data_dir/.pending-file-at-register")" = match ]; then
              echo "PASS  pending marker holds this attempt's manifest before the site is registered"
            else
              echo "FAIL  pending marker holds this attempt's manifest before the site is registered"
              failures=$((failures + 1))
            fi
            # site install's own system integration resolves the .desktop
            # entry and icon directory from XDG_DATA_HOME, so the installer
            # must pin it from xdgDataHome itself rather than leave it to
            # whatever the caller's environment happens to hold; this
            # environment's own XDG_DATA_HOME (above) is deliberately wrong.
            if [ "$(cat "$data_dir/.xdg-data-home-seen")" = "$pinned_xdg_data_home" ]; then
              echo "PASS  XDG_DATA_HOME is pinned from xdgDataHome, not the caller's environment"
            else
              echo "FAIL  XDG_DATA_HOME is pinned from xdgDataHome, not the caller's environment"
              failures=$((failures + 1))
            fi
            expect "second run no-ops" 0 "already installed with current URL"
            set_url 'https://mail.example.com/u/1?tok=a'
            expect "same-origin rotation refreshes" 0 "updated start URL"
            expect "no-op after rotation" 0 "already installed with current URL"

            # A marker surviving a kill between record_ulid and its own
            # removal must not persist once ulid_file already names this
            # site: neither the no-op path above nor the refresh path below
            # ever touches it otherwise, so it would sit on disk for the
            # life of the install.
            : >"$data_dir/dmail-installing"
            expect "a marker surviving past record_ulid still no-ops" 0 \
              "already installed with current URL"
            if [ -e "$data_dir/dmail-installing" ]; then
              echo "FAIL  no-op clears a marker left behind by an earlier kill"
              failures=$((failures + 1))
            else
              echo "PASS  no-op clears a marker left behind by an earlier kill"
            fi

            # site update itself failing (for example storage.write erroring
            # on the rewrite) must be reported, not silently swallowed.
            set_url 'https://mail.example.com/u/2?tok=b'
            STUB_FAIL_UPDATE=1 expect "site update failure reports" 1 \
              "failed to update start URL"

            echo "-- refusals --"
            set_url 'https://other.example.org/x'
            expect "cross-origin rotation refuses" 1 "does not match the installed origin"
            expect "cross-origin refusal repeats" 1 "does not match the installed origin"
            # Deleting either record skips the guard rather than satisfying it,
            # so the refusal must not name a path whose removal offers that as
            # a way out. Matched on the filename alone, not a verb: "remove",
            # "delete" and "rm" are all the same bypass, and naming the marker
            # under any wording is the failure this assertion exists to catch.
            # Captured first and matched with case, not piped into grep: the
            # installer exits 1 here, and under pipefail either its own status
            # or a SIGPIPE from grep -q exiting early would decide the `if` no
            # matter what the text was.
            refusal=$("$installer" 2>&1 || true)
            case "$refusal" in
              *dmail-applied-url*)
                echo "FAIL  refusal names the marker, whose removal bypasses the guard"
                failures=$((failures + 1))
                ;;
              *) echo "PASS  refusal does not name the marker" ;;
            esac
            set_url 'not-a-url'
            expect "unparsable secret refuses" 1 "cannot derive an origin"
            : >"$url_file"
            expect "empty secret refuses" 1 "decrypted URL is empty"
            rm -f "$url_file"
            expect "missing secret refuses" 1 "secret not readable"

            echo "-- url crate normalizations must not refuse same-origin rotations --"
            reset
            set_url 'HTTPS://Mail.Example.COM/a'
            expect "uppercase scheme and host install" 0 "installed 'DMail'"
            set_url 'HTTPS://Mail.Example.COM/b'
            expect "uppercase rotation refreshes" 0 "updated start URL"
            set_url 'https://mail.example.com/c'
            expect "case-changed secret refreshes" 0 "updated start URL"

            reset
            set_url 'https://mail.example.com:443/a'
            "$installer" >/dev/null
            set_url 'https://mail.example.com:443/b'
            expect "explicit default port refreshes" 0 "updated start URL"

            reset
            set_url 'https://mail.example.com/a'
            "$installer" >/dev/null
            set_url 'https://mail.example.com:443/b'
            expect "added default port refreshes" 0 "updated start URL"

            reset
            set_url 'https://${idnHost}/a'
            "$installer" >/dev/null
            assert_equal "IDN scope is punycoded by the stub" \
              "$(jq -r '.sites["01STUB"].manifest.scope' "$config_file")" \
              'https://${idnPunycode}/'
            set_url 'https://${idnHost}/b'
            expect "IDN host refreshes" 0 "updated start URL"

            echo "-- a partial install must not be recorded as applied --"
            reset
            set_url 'https://mail.example.com/x'
            STUB_FAIL_AFTER_REGISTER=1 "$installer" >/dev/null 2>&1 && {
              echo "FAIL  failed install reported success"
              failures=$((failures + 1))
            }
            if [ -e "$marker" ]; then
              echo "FAIL  failed install wrote the applied marker"
              failures=$((failures + 1))
            else
              echo "PASS  failed install left no marker"
            fi
            expect "next activation repairs the partial install" 0 "updated start URL"
            expect "repaired install then no-ops" 0 "already installed with current URL"

            # A stale applied_file surviving a full install from before the
            # site was removed outside this unit (uninstalling does not clear
            # this script's records) can already equal the unrotated secret,
            # so the failed-after-register branch must drop it too: otherwise
            # the no-op fast path matches ulid_file and the stale marker both,
            # and the site update this branch exists to schedule never runs.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            jq '.sites = {}' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            STUB_FAIL_AFTER_REGISTER=1 "$installer" >/dev/null 2>&1 || true
            expect "failed-after-register repairs rather than no-ops on a stale marker" 0 \
              "updated start URL"

            # A partial install leaves no applied-URL marker, so the origin it
            # established is the only thing the guard can test against.
            reset
            set_url 'https://mail.example.com/x'
            STUB_FAIL_AFTER_REGISTER=1 "$installer" >/dev/null 2>&1 || true
            set_url 'https://other.example.org/x'
            expect "rotation after a partial install refuses" 1 "does not match the installed origin"

            # All three attempts fail before the site is ever registered:
            # retryDelay = 0 in this check keeps this real (no sleep), unlike
            # a bare reading of the retry loop's control flow. The loop must
            # give up after the third attempt, not print a fourth "retrying"
            # that never happens, and record_applied must never run.
            reset
            set_url 'https://mail.example.com/x'
            STUB_FAIL_BEFORE_REGISTER=1 expect "exhausted retries fail" 1 \
              "install failed after 3 attempts"
            if [ -e "$marker" ]; then
              echo "FAIL  exhausted retries wrote the applied marker"
              failures=$((failures + 1))
            else
              echo "PASS  exhausted retries left no marker"
            fi

            # origin_file must not survive exhausted retries either: it would
            # describe a site that was never created, and later outrank the
            # "nothing records the origin" refusal for whatever comes to carry
            # this name next, for example a site installed by hand from the
            # browser extension. Simulated directly, since the stub has no
            # install path for that.
            jq '.sites["01FOREIGN"] = {
                  config: {
                    name: "DMail",
                    start_url: "https://mail.example.com/u/0/",
                    document_url: "https://mail.example.com/u/0/",
                    manifest_url: "data:,"
                  },
                  manifest: {scope: "https://mail.example.com/u/0/"}
                }' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            expect "site installed after exhausted retries is not adopted" 1 \
              "nothing records the origin"

            # The sibling case above runs after reset, so applied_file was
            # never written and the elif fallback it exercises is reached
            # with nothing there either. A stale applied_file specifically,
            # left behind by an earlier install that "firefoxpwa site
            # uninstall" does not clear (removal is one-way, per this
            # option's own description), must not survive exhausted retries
            # any more than origin_file does: otherwise the elif branch would
            # derive a guard_origin from it, and a same-origin rotation would
            # match and adopt whatever comes to carry this name next.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            jq '.sites = {}' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            set_url 'https://mail.example.com/y'
            STUB_FAIL_BEFORE_REGISTER=1 "$installer" >/dev/null 2>&1 || true
            jq '.sites["01FOREIGN"] = {
                  config: {
                    name: "DMail",
                    start_url: "https://other.example.org/u/0/",
                    document_url: "https://other.example.org/u/0/",
                    manifest_url: "data:,"
                  },
                  manifest: {scope: "https://other.example.org/u/0/"}
                }' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            expect "stale applied-URL marker does not adopt a site after exhausted retries" 1 \
              "nothing records the origin"

            # A site carrying the managed name that neither record accounts for:
            # its scope is unknown, so refreshing it could put start_url outside.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            rm -f "$marker" "$data_dir/dmail-applied-origin"
            set_url 'https://mail.example.com/y'
            expect "unrecorded site refuses" 1 "nothing records the origin"

            # Only the origin record is gone: the guard must fall back to
            # re-deriving the origin from the applied URL (the elif branch in
            # default.nix). Covers a site installed before dmail-applied-origin
            # existed; record_origin running unconditionally before every
            # install since means origin_file is otherwise always present, and
            # nothing else in this file removes only it.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            rm -f "$data_dir/dmail-applied-origin"
            set_url 'https://mail.example.com/y'
            expect "origin recovered from the applied URL refreshes" 0 "updated start URL"
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            rm -f "$data_dir/dmail-applied-origin"
            set_url 'https://other.example.org/x'
            expect "origin recovered from the applied URL still refuses" 1 \
              "does not match the installed origin"

            # firefoxpwa writes config.json through File::create with no
            # rename, and firefoxpwa connector can be rewriting it when this
            # unit runs (PartOf reruns it on every switch). site_ulid failing
            # to parse the file must not read as "no site": falling through to
            # install would register a second one under the same name.
            # Matched on the "installing a second" wording specifically, not
            # just "cannot read": the retry loop's own site_ulid call has an
            # identical guard and a similarly worded message, and the stub's
            # write_site parses the same file, so a malformed config.json
            # that reaches firefoxpwa site install fails there too. A generic
            # substring would pass on that fallthrough and prove nothing
            # about this check specifically.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            printf 'not valid json' >"$config_file"
            expect "unreadable config.json refuses rather than risking a duplicate" 1 \
              "not installing a second"

            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            : >"$config_file"
            expect "zero-byte config.json refuses rather than risking a duplicate" 1 \
              "not installing a second"

            # Following the refusal's own remedy: installed at A, rotated to B,
            # site uninstalled, then the reinstall registers and fails. The
            # applied URL still names A while the origin record names B, so
            # preferring the stale URL would refuse forever.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            set_url 'https://other.example.org/x'
            expect "cross-origin rotation refuses before the uninstall" 1 "does not match the installed origin"
            jq '.sites = {}' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            STUB_FAIL_AFTER_REGISTER=1 "$installer" >/dev/null 2>&1 || true
            expect "reinstall at the new origin is not blocked by the old URL" 0 "updated start URL"

            # Origin bookkeeping alone never authenticated the site, only
            # where it claims to be installed. Uninstalling a site does not
            # clear these records (one-way, per this option's own docs), so
            # a same-named site created by hand afterward, at the SAME
            # origin, would pass every origin check that exists and still be
            # a site this script never installed. ulid_file is the guard
            # that actually distinguishes them.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            jq '.sites = {}' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            jq '.sites["01FOREIGN"] = {
                  config: {
                    name: "DMail",
                    start_url: "https://mail.example.com/u/0/",
                    document_url: "https://mail.example.com/u/0/",
                    manifest_url: "data:,"
                  },
                  manifest: {scope: "https://mail.example.com/u/0/"}
                }' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            set_url 'https://mail.example.com/z'
            expect "foreign site after an ordinary uninstall is not adopted" 1 \
              "is not the site this unit installed"

            # Same scenario, secret left unrotated: the no-op fast path ran
            # before any identity check, so applied_file matching the
            # unchanged URL would silently report success for a foreign
            # site, the steady state rather than an edge case, unlike the
            # sibling case above which only ever exercises the path where
            # the no-op is skipped by a rotation.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            jq '.sites = {}' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            jq '.sites["01FOREIGN"] = {
                  config: {
                    name: "DMail",
                    start_url: "https://mail.example.com/u/0/",
                    document_url: "https://mail.example.com/u/0/",
                    manifest_url: "data:,"
                  },
                  manifest: {scope: "https://mail.example.com/u/0/"}
                }' "$config_file" >"$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            expect "foreign site with an unrotated secret is not treated as a no-op" 1 \
              "is not the site this unit installed"

            # ulid_file can go missing for a site this script genuinely
            # installed: a kill between firefoxpwa site install succeeding
            # and record_ulid completing, or a site_ulid read racing
            # firefoxpwa connector right after install. Simulated directly,
            # since a real kill mid-script cannot be induced through the
            # stub: config.json carries the site and origin_file and
            # pending_file are what the pre-loop writes leave behind, but
            # ulid_file was never reached. pending_file must let this repair
            # rather than refuse a site the unit did install: its content
            # here matches the site's own manifest_url, the same match the
            # adopt check requires.
            reset
            set_url 'https://mail.example.com/x'
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01STUB"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: "data:,"
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            printf '%s' 'https://mail.example.com' >"$data_dir/dmail-applied-origin"
            printf '%s' 'data:,' >"$data_dir/dmail-installing"
            expect "interrupted ulid recording repairs instead of refusing" 0 \
              "updated start URL"

            # ulid_file can also be stale, not just missing: firefoxpwa site
            # uninstall (the remedy every refusal here names) clears none of
            # this script's own records, so a later install that registers a
            # new site under this name but does not reach record_ulid, for
            # example the retry loop's own config.json read race, ends with
            # the previous ulid still on disk rather than no ulid at all.
            # That is not a foreign site either: the marker's content is
            # what proves it, the same as when ulid_file is absent, so the
            # repair must not require ulid_file to be missing specifically.
            reset
            set_url 'https://mail.example.com/x'
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01NEW"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: "data:,"
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            printf '%s' 'https://mail.example.com' >"$data_dir/dmail-applied-origin"
            printf '%s' '01OLD' >"$data_dir/dmail-applied-ulid"
            printf '%s' 'data:,' >"$data_dir/dmail-installing"
            expect "stale ulid_file from an earlier install still repairs" 0 \
              "updated start URL"

            # The repair above must not extend to a genuine foreign site:
            # without a pending_file, a missing ulid_file still refuses.
            reset
            set_url 'https://mail.example.com/x'
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01FOREIGN"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: "data:,"
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            printf '%s' 'https://mail.example.com' >"$data_dir/dmail-applied-origin"
            expect "foreign site with no pending install still refuses" 1 \
              "is not the site this unit installed"

            # A kill before storage.write registers a site (record_origin
            # and pending_file are both written before every attempt, so
            # both exist; nothing else does) must not leave anything that
            # later licenses adopting a foreign same-named site appearing at
            # that origin. pending_file is empty here, matching a marker
            # written moments before such a kill: it cannot equal any real
            # manifest_url, so the adopt check's match requirement refuses
            # regardless of what the foreign site's own manifest_url is.
            reset
            set_url 'https://mail.example.com/x'
            printf '%s' 'https://mail.example.com' >"$data_dir/dmail-applied-origin"
            : >"$data_dir/dmail-installing"
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01FOREIGN"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: "data:,"
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            expect "foreign site after a kill before registration still refuses" 1 \
              "is not the site this unit installed"

            # pending_file's content must match, not just exist: a foreign
            # site with its own manifest_url is not adopted merely because
            # this script left a marker behind for a different attempt.
            reset
            set_url 'https://mail.example.com/x'
            printf '%s' 'https://mail.example.com' >"$data_dir/dmail-applied-origin"
            printf '%s' 'data:application/manifest+json;base64,e30=' \
              >"$data_dir/dmail-installing"
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01FOREIGN"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: "data:,"
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            expect "foreign site with a mismatched manifest still refuses" 1 \
              "is not the site this unit installed"

            # Both sides of the content match can independently land on an
            # empty string: an empty marker (a kill between this attempt's
            # truncating write and the printf that follows it) and a
            # manifest_url jq cannot find at all (missing from the foreign
            # site's own config, or a config.json read racing firefoxpwa
            # connector's rewrite). Together they satisfied "" = "" under a
            # presence check; requiring the marker itself to be non-empty
            # refuses regardless of what jq reads on the other side.
            reset
            set_url 'https://mail.example.com/x'
            printf '%s' 'https://mail.example.com' >"$data_dir/dmail-applied-origin"
            : >"$data_dir/dmail-installing"
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01FOREIGN"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            expect "foreign site with no manifest_url still refuses" 1 \
              "is not the site this unit installed"

            # config.json can race firefoxpwa connector's own rewrite right
            # after this call registers the site: site_ulid then fails to
            # read it rather than finding nothing (STUB_LOSE_REGISTRATION's
            # case). pending_file and origin_file must survive this exit,
            # the opposite of the neighbouring [ -z "$ulid" ] branch, so a
            # later run with config.json readable again repairs the site
            # this call did register instead of refusing it or installing
            # a duplicate.
            reset
            set_url 'https://mail.example.com/x'
            STUB_CORRUPT_AFTER_REGISTER=1 expect \
              "install succeeding with an unreadable config.json fails" 1 \
              "after installing"
            if [ -r "$data_dir/dmail-applied-origin" ] && [ -s "$data_dir/dmail-installing" ]; then
              echo "PASS  origin_file and pending_file survive an unreadable config.json"
            else
              echo "FAIL  origin_file and pending_file survive an unreadable config.json"
              failures=$((failures + 1))
            fi
            jq -n --arg m "$(cat "$data_dir/dmail-installing")" --arg s 'https://mail.example.com/' \
              '.sites["01STUB"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: $m
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            expect "repair after config.json becomes readable again" 0 \
              "updated start URL"

            # The same race can also land on a failed attempt: firefoxpwa
            # site install itself fails, but the site it registered before
            # failing (the window STUB_FAIL_AFTER_REGISTER alone tests) is
            # then unreadable rather than absent. pending_file and
            # origin_file must survive here too, for the same reason.
            reset
            set_url 'https://mail.example.com/x'
            STUB_CORRUPT_AFTER_REGISTER=1 STUB_FAIL_AFTER_REGISTER=1 expect \
              "failed install with an unreadable config.json does not retry" 1 \
              "not retrying install"
            if [ -r "$data_dir/dmail-applied-origin" ] && [ -s "$data_dir/dmail-installing" ]; then
              echo "PASS  origin_file and pending_file survive a failed attempt's unreadable config.json"
            else
              echo "FAIL  origin_file and pending_file survive a failed attempt's unreadable config.json"
              failures=$((failures + 1))
            fi
            jq -n --arg m "$(cat "$data_dir/dmail-installing")" --arg s 'https://mail.example.com/' \
              '.sites["01STUB"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: $m
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            expect "repair after a failed attempt's config.json becomes readable" 0 \
              "updated start URL"

            # firefoxpwa can report success while site_ulid finds nothing
            # under $app_name (for example a read racing firefoxpwa
            # connector's own write to config.json). That exit must not
            # leave anything that later licenses adopting a foreign
            # same-named site appearing at the recorded origin, the same
            # reasoning as the exhausted-retries cleanup: pending_file was
            # written for an install this run cannot prove happened.
            reset
            set_url 'https://mail.example.com/x'
            STUB_LOSE_REGISTRATION=1 expect \
              "install reporting success with no registered site still fails" 1 \
              "reported installed but is not in"
            jq -n --arg s 'https://mail.example.com/' \
              '.sites["01FOREIGN"] = {
                 config: {
                   name: "DMail",
                   start_url: "https://mail.example.com/x",
                   document_url: $s,
                   manifest_url: "data:,"
                 },
                 manifest: {scope: $s}
               }' >"$config_file"
            expect "foreign site after a lost registration still refuses" 1 \
              "is not the site this unit installed"

            echo "-- the secret reaches only the field rotation can rewrite --"
            reset
            set_url 'https://mail.example.com/inbox?token=TOK_FIRST'
            "$installer" >/dev/null
            assert_equal "token lands only in start_url" \
              "$(jq -r '.sites["01STUB"].config | to_entries | map(select(.value | tostring | test("TOK_FIRST")) | .key) | join(",")' "$config_file")" \
              'start_url'
            assert_equal "document_url holds the origin" \
              "$(jq -r '.sites["01STUB"].config.document_url' "$config_file")" \
              'https://mail.example.com/'
            # start_url is the only field site update can rewrite, so the decoded
            # manifest must not carry the token either: manifest_url is immutable.
            manifest_text=$(decoded_manifest)
            case "$manifest_text" in
              *TOK_FIRST*)
                echo "FAIL  manifest URL carries the token"
                failures=$((failures + 1))
                ;;
              *) echo "PASS  manifest URL carries no token" ;;
            esac
            set_url 'https://mail.example.com/inbox?token=TOK_SECOND'
            "$installer" >/dev/null
            assert_absent "rotation retires the previous token" TOK_FIRST

            # A credentials-bearing secret cannot be installed consistently:
            # url_origin drops userinfo for scope/document_url, so start_url
            # (which must keep the secret for navigation) would fall outside
            # its own scope, and site update can rewrite neither field
            # afterwards. Refused rather than silently installed in that
            # inconsistent state.
            reset
            set_url 'https://user:TOK_USERINFO@mail.example.com/inbox'
            expect "credentials-bearing secret refuses" 1 "embeds credentials"
            if [ -e "$config_file" ]; then
              echo "FAIL  refused secret still wrote config.json"
              failures=$((failures + 1))
            else
              echo "PASS  refused secret wrote nothing"
            fi

            echo "-- scope is the bare origin even for a root URL with a query --"
            reset
            set_url 'https://mail.example.com?q=1'
            "$installer" >/dev/null
            assert_equal "scope is origin-only" \
              "$(jq -r '.sites["01STUB"].manifest.scope' "$config_file")" \
              'https://mail.example.com/'
            assert_equal "marker is owner-only" "$(stat -c '%a' "$marker")" 600
            assert_equal "marker holds the secret verbatim" \
              "$(cat "$marker")" 'https://mail.example.com?q=1'
            # Hygiene only. record_applied's atomicity is not asserted here: an
            # in-place write leaves no sibling either, and telling the two apart
            # needs a fault injected between truncation and write.
            if [ -e "$marker.next" ]; then
              echo "FAIL  marker temporary file left behind"
              failures=$((failures + 1))
            else
              echo "PASS  marker write leaves no temporary"
            fi

            echo
            echo "-- renaming the site is refused rather than orphaning it --"
            reset
            set_url 'https://mail.example.com/a'
            "$installer" >/dev/null
            expect "rename refused" 1 "is a new name for the site this unit installed" "$renamed"
            assert_equal "no second site registered under the new name" \
              "$(jq -r '(.sites // {}) | length' "$config_file")" 1
            # The site's own name, not the count or the ulid record: this stub
            # writes every install to .sites["01STUB"], so without the guard the
            # renamed run overwrites the original rather than adding one, and
            # both of those read identically either way.
            assert_equal "the installed site still carries the original name" \
              "$(jq -r '.sites["01STUB"].config.name' "$config_file")" "DMail"
            # config.json gone entirely rather than the site removed from it:
            # the rename guard reads that file, so it has to tell "no file" from
            # "cannot read this file" and let the first install.
            rm -f "$config_file"
            # The full message, not just "installed": that substring also matches
            # "already installed with current URL", so the loose form pins
            # neither the branch that ran nor the name it installed under.
            expect "a config.json that is gone does not block the install" 0 "installed 'Work Mail'" "$renamed"

            reset
            set_url 'https://mail.example.com/a'
            "$installer" >/dev/null
            expect "rename still refused after the reset" 1 "is a new name for the site this unit installed" "$renamed"
            # An uninstall leaves the same record but takes the site, and that
            # case must still install: the guard is on the site being there.
            jq 'del(.sites["01STUB"])' "$config_file" >"$config_file.next"
            mv "$config_file.next" "$config_file"
            expect "an uninstalled site is reinstalled under the new name" 0 "installed 'Work Mail'" "$renamed"
            assert_equal "the reinstalled site carries the new name" \
              "$(jq -r '.sites["01STUB"].config.name' "$config_file")" "Work Mail"

            echo
            echo "-- the installer is built through the shared site installer --"
            # ./site-lock-check.nix proves the builder serializes, but nothing
            # there names this derivation: rewriting default.nix back to a
            # direct writeShellApplication would keep that check green while
            # losing the mutual exclusion it exists to provide. The lock path is
            # the tie, since it is the shared resource rather than the mechanism.
            if grep -q '\.config-lock' "$installer"; then
              echo "PASS  takes the shared site lock"
            else
              echo "FAIL  no shared site lock in the installer text; it was not built through packages/firefoxpwa-site-installer"
              failures=$((failures + 1))
            fi

            echo
            echo "-- the installer uses the directory it is given --"
            if [ -e "$XDG_DATA_HOME/firefoxpwa" ]; then
              echo "FAIL  installer re-derived a path under XDG_DATA_HOME"
              failures=$((failures + 1))
            else
              echo "PASS  nothing written outside the configured data directory"
            fi

            echo
            if [ "$failures" -ne 0 ]; then
              echo "$failures assertion(s) failed"
              exit 1
            fi
            echo "all assertions passed" >"$out"
          '';
    };
}
