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
              scope=$(printf '%s' "''${manifest_url#*base64,}" | base64 -d | jq -r .scope)
              write_site "$manifest_url" "$start_url" "$name" "$document_url" "$scope"
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

      installer = (pkgs.callPackage ../../../packages/firefoxpwa-dmail-install { }) {
        firefoxpwa = stub;
        urlPath = "${secretDir}/url";
        inherit dataDir;
      };
    in
    {
      checks."browsers/firefoxpwa-dmail" =
        pkgs.runCommand "firefoxpwa-dmail-check"
          {
            # Opts this check into the build step in .github/workflows/check.yml.
            # Its assertions run in the derivation, so forcing drvPath proves
            # nothing; the marker keeps that opt-in at the definition site
            # instead of hardcoding a name in the workflow.
            runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.jq
              pkgs.coreutils
            ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            export HOME="$PWD/home"
            # Points somewhere the installer must not use: it is given data_dir
            # explicitly, so anything landing under here is a re-derived path.
            export XDG_DATA_HOME="$PWD/xdg"
            secret_dir=${lib.escapeShellArg secretDir}
            url_file="$secret_dir/url"
            data_dir=${lib.escapeShellArg dataDir}
            config_file="$data_dir/config.json"
            marker="$data_dir/dmail-applied-url"
            # Mirrors the unit's Environment=. The stub resolves its own data
            # directory from this, exactly as firefoxpwa does, so the installer
            # and the binary agree only while both are pinned to it.
            export FFPWA_USERDATA="$data_dir"
            install -d "$HOME" "$XDG_DATA_HOME" "$secret_dir"

            installer=${lib.getExe installer}
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
            expect() {
              local label="$1" want_rc="$2" want_text="$3" out rc=0 ok=1
              out=$("$installer" 2>&1) || rc=$?
              case "$out" in
                *"$want_text"*) [ "$rc" = "$want_rc" ] && ok=0 ;;
              esac
              if [ "$ok" = 0 ]; then
                echo "PASS  $label"
              else
                echo "FAIL  $label (rc=$rc, expected $want_rc)"
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
            expect "second run no-ops" 0 "already installed with current URL"
            set_url 'https://mail.example.com/u/1?tok=a'
            expect "same-origin rotation refreshes" 0 "updated start URL"
            expect "no-op after rotation" 0 "already installed with current URL"

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

            # A partial install leaves no applied-URL marker, so the origin it
            # established is the only thing the guard can test against.
            reset
            set_url 'https://mail.example.com/x'
            STUB_FAIL_AFTER_REGISTER=1 "$installer" >/dev/null 2>&1 || true
            set_url 'https://other.example.org/x'
            expect "rotation after a partial install refuses" 1 "does not match the installed origin"

            # A site carrying the managed name that neither record accounts for:
            # its scope is unknown, so refreshing it could put start_url outside.
            reset
            set_url 'https://mail.example.com/x'
            "$installer" >/dev/null
            rm -f "$marker" "$data_dir/dmail-applied-origin"
            set_url 'https://mail.example.com/y'
            expect "unrecorded site refuses" 1 "nothing records the origin"

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

            # A first install killed after the site was registered but before the
            # script recorded anything. A switch restarts sops-nix and PartOf
            # stops this unit, so the window is routine; the run after it must
            # repair rather than refuse for want of a record.
            reset
            set_url 'https://mail.example.com/x'
            STUB_FAIL_AFTER_REGISTER=1 "$installer" >/dev/null 2>&1 || true
            rm -f "$marker"
            expect "install interrupted before recording still repairs" 0 "updated start URL"

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
