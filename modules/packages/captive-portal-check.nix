/*
  Check: captive-portal classifies a network correctly, and every path that
  released DNS gives it back (packages/captive-portal/captive-portal.sh).

  Nothing executed this script before. It is instantiated only through the host
  overlay in modules/custom-overlays/captive-portal.nix, so a host build lints it
  with shellcheck and stops there, while its decisions all depend on what dig,
  curl, nmcli, ip and tailscale answer on a network that cannot be reached from a
  build.

  Those five are package arguments, so callPackage substitutes stubs for them and
  writeShellApplication's PATH prefix puts the stubs ahead of anything in the
  sandbox: the packaged script runs unmodified against a scripted network.

  Both halves of the contract are load-bearing and both have already been wrong.
  A misclassification either strands the user behind a portal it reported as
  absent, or reports the router as a portal. A missed restore leaves Tailscale
  DNS off after the run exits, which is invisible until the next tailnet name
  fails to resolve.

  /etc/resolv.conf does not exist in the sandbox, which is also what a portal
  that hands out no lease produces, so every scenario reaching show_resolvers
  crosses the `grep '^nameserver' /etc/resolv.conf` that used to abort the run
  between releasing DNS and probing for the portal. One scenario asserts the
  message it prints instead, so the guard has a test that names it rather than
  only an environment that happens to exercise it.

  Two branches stay out of reach here. The builder is uid 1000 and /run is not
  writable, so neither the SUDO_UID fallback for the state directory nor the
  chown that hands the snapshot back to the invoking user can run: both need a
  root process and a /run/user/<uid> that logind made. What is asserted is the
  precedence between them, that an explicit XDG_RUNTIME_DIR still outranks
  SUDO_UID, which is the half a regression would reach every ordinary run.
*/
{
  perSystem =
    { pkgs, ... }:
    {
      checks."packages/captive-portal-runtime" =
        let
          # Answers `debug prefs` from the environment and records every state
          # change, so a scenario can assert on what the run did to DNS.
          # TS_FAIL_STATE names the subcommands that refuse, which is what
          # tailscaled returns to a caller that is neither root nor its operator
          # user, and it is per-subcommand because a failing `up` must not be
          # allowed to look like a failing `set`.
          tailscaleStub = pkgs.writeShellScriptBin "tailscale" ''
            if [ "$*" = "debug prefs" ]; then
              # TS_PREFS_FAIL is the read half of TS_FAIL_STATE: tailscaled
              # answering is not guaranteed either, and a reader that treated a
              # failed read as an answer decided the run silently.
              if [ -n "''${TS_PREFS_FAIL-}" ]; then
                exit 1
              fi
              printf '{"CorpDNS":%s,"WantRunning":%s}\n' \
                "''${TS_CORP_DNS-true}" "''${TS_WANT_RUNNING-true}"
              exit 0
            fi
            printf 'tailscale %s\n' "$*" >>"$CP_LOG"
            case " ''${TS_FAIL_STATE-} " in
            *" $1 "*) exit 1 ;;
            esac
          '';

          # NM_FAIL is a status rather than a flag because the guard's wording
          # depends on which one nmcli returned, and an empty NM_DEVICES cannot
          # stand in for it: that already means "nmcli answered, nothing is
          # connected", which is the case the failure has to be told apart from.
          nmcliStub = pkgs.writeShellScriptBin "nmcli" ''
            case "$*" in
            *"DEVICE,TYPE,STATE device status")
              if [ -n "''${NM_FAIL-}" ]; then
                exit "$NM_FAIL"
              fi
              printf '%b\n' "''${NM_DEVICES-wifi0:wifi:connected}"
              ;;
            *"IP4.DNS device show"*)
              # 10 is nmcli's "device does not exist", which is a different
              # answer from a device that exists and has no DNS (NM_DNS="").
              if [ -n "''${NM_SHOW_FAIL-}" ]; then
                exit "$NM_SHOW_FAIL"
              fi
              printf '%b\n' "''${NM_DNS-IP4.DNS[1]:192.168.1.1}"
              ;;
            *)
              printf 'nmcli %s\n' "$*" >>"$CP_LOG"
              ;;
            esac
          '';

          # Unset means a normal via route; empty means a link with no default
          # route at all, which is what leaves the run without a fallback.
          ipStub = pkgs.writeShellScriptBin "ip" ''
            printf '%b' "''${IP_ROUTE-default via 192.168.1.1 dev wifi0 proto dhcp metric 600\n}"
          '';

          digStub = pkgs.writeShellScriptBin "dig" ''
            host="''${!#}"
            case "$host" in
            detectportal.firefox.com) printf '%s\n' "''${DIG_FIREFOX-203.0.113.10}" ;;
            captive.apple.com) printf '%s\n' "''${DIG_APPLE-203.0.113.11}" ;;
            connectivity-check.gstatic.com) printf '%s\n' "''${DIG_GSTATIC-203.0.113.12}" ;;
            esac
          '';

          # Status 000 stands for a request that never completed, which is what
          # the walled garden does to a host it has not authenticated.
          curlStub = pkgs.writeShellScriptBin "curl" ''
            out=""
            url=""
            noproxy=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
              -o)
                out="$2"
                shift 2
                ;;
              --noproxy)
                noproxy="$2"
                shift 2
                ;;
              http://*)
                url="$1"
                shift
                ;;
              *) shift ;;
              esac
            done
            # --resolve is what makes a status attributable to the address the
            # access point's resolver returned, and an inherited http_proxy
            # silently sends the request somewhere else instead. Nothing this
            # stub can answer would reveal that, so the contract is asserted
            # here: every scenario fails the moment the probe stops pinning it.
            if [ "$noproxy" != "*" ]; then
              echo "curl stub: the probe must pass --noproxy '*'" >&2
              exit 1
            fi
            case "$url" in
            *success.txt)
              status="''${FF_STATUS-200}"
              body="''${FF_BODY-success}"
              redirect="''${FF_REDIRECT-}"
              abort="''${FF_ABORT-}"
              ;;
            *hotspot-detect.html)
              status="''${AP_STATUS-200}"
              body="''${AP_BODY-<HTML><BODY>Success</BODY></HTML>}"
              redirect="''${AP_REDIRECT-}"
              abort="''${AP_ABORT-}"
              ;;
            *generate_204)
              status="''${GS_STATUS-204}"
              body="''${GS_BODY-}"
              redirect="''${GS_REDIRECT-}"
              abort="''${GS_ABORT-}"
              ;;
            *)
              echo "curl stub: unexpected url: $url" >&2
              exit 1
              ;;
            esac
            # The third shape, between "answered" and "never connected": the
            # response line arrived and -m then fired. Real curl writes the -w
            # output, with no terminator, leaves -o untouched, and exits 28.
            # Per-canary like the vars above, because the loop calls curl once per
            # canary and one flag for all three could not place the failure.
            if [ -n "$abort" ]; then
              printf '%s %s' "$status" "$redirect"
              exit 28
            fi
            [ "$status" = 000 ] && exit 7
            printf '%s' "$body" >"$out"
            printf '%s %s' "$status" "$redirect"
          '';

          xdgStub = pkgs.writeShellScriptBin "xdg-open" ''
            printf 'xdg-open %s\n' "$*" >>"$CP_LOG"
          '';

          portal = pkgs.callPackage ../../packages/captive-portal {
            curl = curlStub;
            dnsutils = digStub;
            iproute2 = ipStub;
            networkmanager = nmcliStub;
            tailscale = tailscaleStub;
            xdg-utils = xdgStub;
          };
        in
        pkgs.runCommand "captive-portal-runtime-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = [ pkgs.coreutils ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            work="$PWD/check"
            mkdir -p "$work/run"
            portal=${portal}/bin/captive-portal
            state="$work/run/captive-portal/tailscale-prefs"
            export XDG_RUNTIME_DIR="$work/run"
            export CP_LOG="$work/log"

            fail() {
              echo "packages/captive-portal-runtime: $1" >&2
              echo "--- stdout ---" >&2
              cat "$work/out" >&2
              echo "--- stderr ---" >&2
              cat "$work/err" >&2
              echo "--- tailscale/nmcli calls ---" >&2
              cat "$work/log" >&2
              exit 1
            }

            reset() {
              rm -f "$state" "$work/log"
              : >"$work/log"
            }

            run() {
              rc=0
              "$portal" "$@" >"$work/out" 2>"$work/err" || rc=$?
              printf '%s' "$rc"
            }

            released() {
              grep -qxF 'tailscale set --accept-dns=false' "$work/log"
            }

            restored() {
              grep -qxF 'tailscale set --accept-dns=true' "$work/log"
            }

            # --device swallowing the next flag left the run in login mode, so a
            # request that asked to change nothing released real DNS.
            (
              reset
              rc=$(run --device --probe)
              [ "$rc" -eq 2 ] || fail "--device --probe must be rejected as usage (exit $rc)"
              ! released || fail "--device --probe must not touch DNS"
            )

            # A clean network, and the run that must leave it alone: probe mode
            # touches no DNS, and stdout stays empty so a caller reading it gets
            # a URL only when there is one.
            (
              reset
              rc=$(run --probe)
              [ "$rc" -eq 1 ] || fail "a clean network must exit 1 from --probe (exit $rc)"
              [ ! -s "$work/out" ] || fail "a clean network must print no URL"
              ! released || fail "--probe must not release DNS"
            )

            # The page a probe downloads used to outlive the run: probe_portal is
            # called in a command substitution, so the body_file it created there
            # never reached the parent's cleanup and nothing ever removed it.
            (
              reset
              rm -f "$TMPDIR"/tmp.*
              rc=$(run --probe)
              [ "$rc" -eq 1 ] || fail "a clean network must exit 1 from --probe (exit $rc)"
              leaked="$(find "$TMPDIR" -maxdepth 1 -name 'tmp.*' -print -quit)"
              [ -z "$leaked" ] || fail "the probe body must not outlive the run ($leaked)"
            )

            # The URL is the whole of stdout: every diagnostic goes to stderr.
            (
              reset
              export AP_STATUS=200
              export AP_BODY='<html><a href="http://portal.lan/login">Sign in</a></html>'
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "an intercepted canary must exit 0 (exit $rc)"
              [ "$(cat "$work/out")" = "http://portal.lan/login" ] ||
                fail "stdout must carry the portal URL alone"
            )

            # A portal that answers /generate_204 with 200 and its own page
            # instead of redirecting. The status is the whole answer for that
            # URL, and treating any 200 as clean reported the network as open.
            (
              reset
              export FF_STATUS=000 AP_STATUS=000
              export GS_STATUS=200
              export GS_BODY='<html>Please <a href="http://portal.lan/login">sign in</a></html>'
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "a 200 from generate_204 is the portal, not a clean network (exit $rc)"
              [ "$(cat "$work/out")" = "http://portal.lan/login" ] ||
                fail "the inline portal page must yield its own sign-in URL"
            )

            # The sign-in URL is not simply the first one in the page. An
            # intercepted page served as XHTML opens with the w3.org DTD in its
            # DOCTYPE, and a CDN script tag sits above the form, so matching
            # anywhere in the body launched a browser at w3.org.
            (
              reset
              export FF_STATUS=200
              export FF_BODY='<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><html xmlns="http://www.w3.org/1999/xhtml"><head><script src="http://ajax.googleapis.com/ajax/libs/jquery/1.7/jquery.min.js"></script></head><body><form action="http://portal.lan/login"></form></body></html>'
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "an intercepted XHTML page is still a portal (exit $rc)"
              [ "$(cat "$work/out")" = "http://portal.lan/login" ] ||
                fail "the form target must beat the DTD and the CDN, got '$(cat "$work/out")'"
            )

            # When the only absolute URL a link points at is a validator badge,
            # finding nothing is the better answer: the address that answered the
            # hijacked lookup is at least the host serving the page.
            (
              reset
              export FF_STATUS=200
              export FF_BODY='<html><body><form action="/login"></form><a href="http://validator.w3.org/check?uri=referer">Valid</a></body></html>'
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "a relative form target is still a portal (exit $rc)"
              [ "$(cat "$work/out")" = "http://203.0.113.10" ] ||
                fail "with no usable link the canary's own address must be the URL"
            )

            # A canary that answered correctly from a private address. The
            # hijack check used to run anyway and overrule the payload that had
            # just proved there was no interception.
            (
              reset
              export DIG_FIREFOX=192.168.1.50
              rc=$(run --probe)
              [ "$rc" -eq 1 ] || fail "a correct answer from a private address is not a hijack (exit $rc)"
            )

            # One address per arm of is_private_v4, including each alternative of
            # the 100.64.0.0/10 pattern, which is where a portal answers on
            # carrier networks, and 169.254.0.0/16, which is where it answers
            # before it has issued a lease.
            #
            # All three canaries are forced to 000 so no arm of probe_portal's
            # case matches and the hijack check is what decides. A 200 whose body
            # misses its expected string returns from that arm before reaching
            # is_private_v4, so the earlier form of this loop passed unchanged
            # with those ranges deleted from is_private_v4 outright. Asserting the
            # URL is the second half: the address itself has to be what comes
            # back, not a gateway guess that happens to share the exit status.
            for hijack in \
              10.0.0.1 192.168.1.7 \
              172.16.0.1 172.20.0.1 172.31.0.1 \
              169.254.7.7 \
              100.64.0.1 100.99.0.1 100.100.64.9 100.127.0.1; do
              (
                reset
                export DIG_FIREFOX="$hijack"
                export FF_STATUS=000 AP_STATUS=000 GS_STATUS=000
                rc=$(run --probe)
                [ "$rc" -eq 0 ] || fail "an answer in $hijack's range is a hijack (exit $rc)"
                [ "$(cat "$work/out")" = "http://$hijack" ] ||
                  fail "the hijacked address must be the portal URL, got '$(cat "$work/out")'"
              )
            done

            # The mirror image. Reaching the hijack check is not the same as
            # being a hijack: a canary that never answered, from an address that
            # is nobody's LAN, has to end in the gateway guess instead. 127.0.0.1
            # belongs here rather than in the loop above, because it is this
            # machine: a resolver sinkholing a blocklisted canary there had the
            # run report the user's own host as the portal and open it.
            for miss in 203.0.113.50 127.0.0.1; do
              (
                reset
                export DIG_FIREFOX="$miss"
                export FF_STATUS=000 AP_STATUS=000 GS_STATUS=000
                rc=$(run --probe)
                [ "$rc" -eq 3 ] || fail "$miss must not be reported as a hijack (exit $rc)"
                [ "$(cat "$work/out")" = "http://192.168.1.1" ] ||
                  fail "$miss must fall back to the gateway guess, got '$(cat "$work/out")'"
              )
            done

            # Login mode on a network that turns out to be clean: the release is
            # undone before the run exits, and the snapshot is consumed.
            (
              reset
              rc=$(run --no-open)
              [ "$rc" -eq 1 ] || fail "login mode on a clean network must exit 1 (exit $rc)"
              released || fail "login mode must release DNS"
              restored || fail "a clean network must get DNS back before exit"
              [ ! -e "$state" ] || fail "a completed restore must consume the snapshot"
            )

            # Probes inconclusive and no default route to guess from. This path
            # exited on the spot, leaving Tailscale DNS off with no portal
            # found, no restore, and no reminder.
            (
              reset
              export IP_ROUTE=""
              export DIG_FIREFOX="" DIG_APPLE="" DIG_GSTATIC=""
              rc=$(run --no-open)
              [ "$rc" -eq 3 ] || fail "an inconclusive probe with no gateway must exit 3 (exit $rc)"
              released || fail "login mode must release DNS"
              restored || fail "an inconclusive probe must not strand the release"
              [ ! -e "$state" ] || fail "a completed restore must consume the snapshot"
            )

            # The gateway fallback is the lowest-confidence outcome and must
            # report itself as one: probe_portal's own inconclusive return has
            # to reach the caller as status 3 rather than 2, which is usage.
            (
              reset
              export DIG_FIREFOX="" DIG_APPLE="" DIG_GSTATIC=""
              rc=$(run --probe)
              [ "$rc" -eq 3 ] || fail "a gateway guess must exit 3, not the usage status (exit $rc)"
              [ "$(cat "$work/out")" = "http://192.168.1.1" ] ||
                fail "the gateway guess must be printed as a URL"
              grep -q 'no portal confirmed' "$work/err" ||
                fail "a guess must not be worded like a detection"
            )

            # A guess is printed, not launched: opening the user's own router
            # unasked is worse than showing the address. The guess runs first and
            # the confirmed detection second, so the wait for the detection's
            # xdg-open is also the settle time the guess had to produce one; the
            # script backgrounds that call, so nothing can be asserted the
            # instant it exits.
            (
              reset
              guess_log="$work/log-guess"
              open_log="$work/log-open"
              : >"$guess_log"
              : >"$open_log"

              CP_LOG="$guess_log" DIG_FIREFOX="" DIG_APPLE="" DIG_GSTATIC="" \
                "$portal" >"$work/out" 2>"$work/err" && rc=0 || rc=$?
              [ "$rc" -eq 3 ] || fail "the gateway guess must exit 3 in login mode (exit $rc)"
              grep -q 'was not opened' "$work/err" ||
                fail "the guess must say it was not opened"

              rm -f "$state"
              CP_LOG="$open_log" AP_STATUS=200 \
                AP_BODY='<html><a href="http://portal.lan/login">x</a></html>' \
                "$portal" >"$work/out" 2>"$work/err" && rc=0 || rc=$?
              [ "$rc" -eq 0 ] || fail "a confirmed portal must exit 0 in login mode (exit $rc)"
              waited=0
              until grep -q '^xdg-open ' "$open_log"; do
                waited=$((waited + 1))
                [ "$waited" -le 100 ] || fail "a confirmed portal must be opened in a browser"
                sleep 0.1
              done
              grep -qxF 'xdg-open http://portal.lan/login' "$open_log" ||
                fail "the browser must be handed the portal URL"

              ! grep -q '^xdg-open ' "$guess_log" ||
                fail "a gateway guess must not be opened in a browser"
            )

            # An on-link default route has no via, and reading the third field
            # produced http://wifi0 as the portal URL.
            (
              reset
              export IP_ROUTE='default dev wifi0 scope link\n'
              export DIG_FIREFOX="" DIG_APPLE="" DIG_GSTATIC=""
              rc=$(run --no-open)
              [ "$rc" -eq 3 ] || fail "an on-link default route leaves no gateway to guess (exit $rc)"
              ! grep -q wifi0 "$work/out" || fail "a device name must never be printed as a portal URL"
            )

            # Retrying after a failed sign-in re-snapshotted the released prefs
            # as the originals, and the eventual --restore then read CorpDNS
            # false and left Tailscale DNS off while reporting success.
            (
              reset
              export AP_STATUS=200 AP_BODY='<html><a href="http://portal.lan/">x</a></html>'
              rc=$(run --no-open)
              [ "$rc" -eq 0 ] || fail "a detected portal must exit 0 (exit $rc)"
              [ -e "$state" ] || fail "a detected portal must leave the snapshot for --restore"

              # The retry sees the state the first run created.
              rc=$(TS_CORP_DNS=false run --no-open)
              [ "$rc" -eq 0 ] || fail "a retry must still report the portal (exit $rc)"
              [ "$(cat "$state")" = "$(printf 'true\ttrue')" ] ||
                fail "a retry must not overwrite the original prefs with the released ones"

              : >"$work/log"
              rc=$(TS_CORP_DNS=false run --restore)
              [ "$rc" -eq 0 ] || fail "--restore must succeed after a retry (exit $rc)"
              restored || fail "--restore after a retry must hand DNS back"
            )

            # SUDO_UID names the state directory only because the sudo env reset
            # took XDG_RUNTIME_DIR away with it. A runtime directory the caller
            # set is the caller's answer and has to outrank it, or a `sudo -E`
            # run would write where the session that exported it never looks.
            (
              reset
              export SUDO_UID=12345 SUDO_GID=12345
              export AP_STATUS=200 AP_BODY='<html><a href="http://portal.lan/">x</a></html>'
              rc=$(run --no-open)
              [ "$rc" -eq 0 ] || fail "SUDO_UID must not change a detected portal (exit $rc)"
              [ -s "$state" ] || fail "an explicit XDG_RUNTIME_DIR must outrank SUDO_UID"
            )

            # A snapshot truncated by a failed `tailscale debug prefs` used to
            # kill --restore on the unguarded read, before it restored anything,
            # and every later --restore repeated the abort.
            for content in "" "garbage" "true"; do
              (
                reset
                mkdir -p "$(dirname "$state")"
                printf '%s' "$content" >"$state"
                rc=$(run --restore)
                [ "$rc" -eq 0 ] || fail "--restore must survive a state file holding '$content' (exit $rc)"
                restored || fail "an unusable state file must restore DNS rather than assume it stays off"
                [ ! -e "$state" ] || fail "--restore must consume the unusable state file"
              )
            done

            # An honest snapshot is still replayed exactly: a host that had
            # accept-dns off before the run must not have it turned on.
            (
              reset
              mkdir -p "$(dirname "$state")"
              printf 'false\ttrue\n' >"$state"
              rc=$(run --restore)
              [ "$rc" -eq 0 ] || fail "--restore must succeed for a saved false (exit $rc)"
              ! restored || fail "a saved CorpDNS false must not be turned on"
              # The branch was pinned and the message was not, so it drifted:
              # this run reported DNS as handed back on the one path that
              # deliberately does not hand it back.
              ! grep -q 'DNS returned to Tailscale' "$work/err" ||
                fail "a saved CorpDNS false must not be reported as DNS handed back"
              grep -q 'so it was left off' "$work/err" ||
                fail "a saved CorpDNS false must say DNS was left off"
            )

            # Nothing declared an operator user for tailscaled, so the release is
            # refused. `debug prefs` answers anyway, so the run had already
            # written a snapshot of a state it then failed to leave.
            (
              reset
              rc=$(TS_FAIL_STATE=set run --no-open)
              [ "$rc" -eq 4 ] || fail "a refused release must exit 4 (exit $rc)"
              grep -q 'operator' "$work/err" ||
                fail "a refused release must name the operator pref"
              [ ! -e "$state" ] ||
                fail "a release that changed nothing must not leave a snapshot to replay"
              [ ! -s "$work/out" ] || fail "a refused release must print no URL"
            )

            # The mirror image: --restore is refused, DNS stays released, and the
            # snapshot is the only record of what to put back.
            (
              reset
              mkdir -p "$(dirname "$state")"
              printf 'true\ttrue\n' >"$state"
              rc=$(TS_FAIL_STATE=set run --restore)
              [ "$rc" -eq 4 ] || fail "a refused restore must exit 4 (exit $rc)"
              [ -s "$state" ] || fail "a refused restore must keep the snapshot for a retry"
              grep -q 'captive-portal --restore' "$work/err" ||
                fail "a refused restore must say how to retry"
            )

            # `tailscale up` used to run first and gate the DNS restore, so a node
            # that would not come back up kept its resolvers off for no reason.
            # It no longer does, so the rest of the restore must not behave as if
            # it had: the failure is reported as its own, not as the operator wall
            # the DNS write had already cleared, and the reload that finishes the
            # DNS half still runs even though the run exits nonzero.
            (
              reset
              mkdir -p "$(dirname "$state")"
              printf 'true\ttrue\n' >"$state"
              rc=$(TS_WANT_RUNNING=false TS_FAIL_STATE=up run --restore)
              [ "$rc" -eq 4 ] || fail "a refused up must still exit 4 (exit $rc)"
              restored || fail "a refused up must not keep DNS from Tailscale"
              [ -s "$state" ] || fail "an incomplete restore must keep the snapshot"
              ! grep -q 'operator' "$work/err" ||
                fail "a refused up is not the operator wall and must not name it"
              ! grep -q 'DNS is still released' "$work/err" ||
                fail "a refused up must not report DNS it just handed back as released"
              grep -qxF 'nmcli general reload dns-full' "$work/log" ||
                fail "a restored resolver still needs the NetworkManager reload"
            )

            # The run state was read straight into a comparison, so a failed read
            # became an empty string, compared unequal to false, and skipped the
            # restart the snapshot had asked for without a word.
            (
              reset
              mkdir -p "$(dirname "$state")"
              printf 'true\ttrue\n' >"$state"
              rc=$(TS_PREFS_FAIL=1 run --restore)
              [ "$rc" -eq 4 ] || fail "an unreadable prefs read must exit 4 (exit $rc)"
              restored || fail "an unreadable prefs read must not keep DNS from Tailscale"
              [ -s "$state" ] || fail "an incomplete restore must keep the snapshot"
              ! grep -qxF 'tailscale up' "$work/log" ||
                fail "an unknown run state must not be guessed at"
              grep -q 'whether the node needs starting is unknown' "$work/err" ||
                fail "an unreadable prefs read must say so"
            )

            # save_prefs ran with errexit suspended, because `if ! save_prefs` is
            # its only caller, and ended in an assignment, so mkdir, mktemp, the
            # write and the mv could all fail while the function still reported
            # success and the run released DNS with nothing recorded. Both shapes
            # reach it: the directory that cannot be created, and the one that
            # exists and cannot be written.
            (
              reset
              runtime="$work/denied-create"
              mkdir -p "$runtime"
              chmod 500 "$runtime"
              rc=$(XDG_RUNTIME_DIR="$runtime" run --no-open)
              chmod 700 "$runtime"
              [ "$rc" -eq 4 ] || fail "a state directory that cannot be created must exit 4 (exit $rc)"
              ! released || fail "a run that cannot record the prefs must not release DNS"
              # The script's own prefix, because mkdir's stderr says "cannot
              # create directory" too and matching that passed with no guard.
              grep -q '^captive-portal: cannot create' "$work/err" ||
                fail "the run must say the state directory could not be created"
            )

            (
              reset
              runtime="$work/denied-write"
              mkdir -p "$runtime/captive-portal"
              chmod 500 "$runtime/captive-portal"
              rc=$(XDG_RUNTIME_DIR="$runtime" run --no-open)
              chmod 700 "$runtime/captive-portal"
              [ "$rc" -eq 4 ] || fail "a state directory that cannot be written must exit 4 (exit $rc)"
              ! released || fail "a run that cannot record the prefs must not release DNS"
              grep -q '^captive-portal: cannot write' "$work/err" ||
                fail "the run must say the snapshot could not be written"
            )

            # Absence of a snapshot is not evidence the node was ever up: the
            # WantRunning default started a node the user had stopped on purpose.
            (
              reset
              rc=$(TS_WANT_RUNNING=false run --restore)
              [ "$rc" -eq 0 ] || fail "--restore without a snapshot must succeed (exit $rc)"
              restored || fail "--restore without a snapshot must still hand DNS back"
              ! grep -qxF 'tailscale up' "$work/log" ||
                fail "--restore must not start a node no snapshot says was running"
            )

            # The --down half of the retry contract: the second run must not
            # record the WantRunning it just set, or --restore leaves the node down.
            (
              reset
              export AP_STATUS=200 AP_BODY='<html><a href="http://portal.lan/">x</a></html>'
              rc=$(run --no-open --down)
              [ "$rc" -eq 0 ] || fail "a detected portal must exit 0 under --down (exit $rc)"
              grep -qxF 'tailscale down' "$work/log" || fail "--down must stop Tailscale"

              rc=$(TS_WANT_RUNNING=false run --no-open --down)
              [ "$rc" -eq 0 ] || fail "a retry under --down must still report the portal (exit $rc)"
              [ "$(cat "$state")" = "$(printf 'true\ttrue')" ] ||
                fail "a retry must not record the WantRunning the first run set"

              : >"$work/log"
              rc=$(TS_WANT_RUNNING=false run --restore)
              [ "$rc" -eq 0 ] || fail "--restore after --down must succeed (exit $rc)"
              grep -qxF 'tailscale up' "$work/log" ||
                fail "--restore must start the node --down stopped"
              # The pair to the refused-up scenario: where that one proves DNS
              # goes back even when the node does not, this one proves a
              # succeeding `up` still leaves the DNS half and the snapshot done.
              restored || fail "--restore must hand DNS back when --down stopped the node"
              [ ! -e "$state" ] || fail "a completed restore must consume the snapshot"
            )

            # --down on a network that turns out clean. Stopping the node is the
            # whole of what --down changes: adding an accept-dns release on top
            # would be a second undo for --restore to get wrong.
            (
              reset
              rc=$(run --no-open --down)
              [ "$rc" -eq 1 ] || fail "--down on a clean network must exit 1 (exit $rc)"
              grep -qxF 'tailscale down' "$work/log" ||
                fail "--down must stop the node rather than release DNS"
              ! released || fail "--down must not also set accept-dns=false"
            )

            # A portal that redirects rather than serving its page inline. Neither
            # 30x path had a scenario, so the branch that reads Location was free
            # to break silently.
            (
              reset
              export FF_STATUS=302 FF_REDIRECT=http://portal.lan/welcome
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "a 302 to the portal must exit 0 (exit $rc)"
              [ "$(cat "$work/out")" = "http://portal.lan/welcome" ] ||
                fail "the redirect target must be the portal URL"
            )

            # A transfer that died after the response line. curl had already
            # written its unterminated -w output, so `|| echo '000 '` landed on
            # that same line: `read` took curl's http_code as the status and the
            # fallback's own text as the redirect, and the 30x arm printed
            # http://portal.lan/welcome000 as the portal. Nothing a failed
            # transfer printed may decide the run.
            (
              reset
              export FF_STATUS=302 FF_REDIRECT=http://portal.lan/welcome FF_ABORT=1
              rc=$(run --probe)
              [ "$rc" -eq 1 ] || fail "an aborted canary must not decide the run (exit $rc)"
              [ ! -s "$work/out" ] ||
                fail "an aborted transfer must print no URL, got '$(cat "$work/out")'"
            )

            # Dropping what it printed is not the same as dropping the canary: the
            # DNS answer stands, and an answer on this LAN is the hijack the probe
            # exists to find, so the fall-through has to reach that check.
            (
              reset
              export DIG_FIREFOX=192.168.1.42 FF_ABORT=1
              export AP_STATUS=000 GS_STATUS=000
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "an aborted canary must still reach the hijack check (exit $rc)"
              [ "$(cat "$work/out")" = "http://192.168.1.42" ] ||
                fail "the hijacked address must still be the portal URL"
            )

            # RFC 6585's status for exactly this: a proxy portal that intercepts
            # HTTP without touching DNS, so the canary resolves to its real
            # public address and the status is the only tell. No arm matched it,
            # so all three canaries fell through and the run printed the gateway
            # as an unconfirmed guess while the body it had just fetched carried
            # the sign-in link.
            (
              reset
              export FF_STATUS=511 FF_BODY='<html><a href="http://portal.lan/login">Sign in</a></html>'
              export AP_STATUS=511 GS_STATUS=511
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "a 511 is a portal by definition (exit $rc)"
              [ "$(cat "$work/out")" = "http://portal.lan/login" ] ||
                fail "the 511 body's sign-in link must be the portal URL"
            )

            # A 511 is never clean, however its body happens to read: only a 200
            # can clear a canary by carrying what that canary was told to expect.
            (
              reset
              export FF_STATUS=511 FF_BODY=success
              export AP_STATUS=000 GS_STATUS=000
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "a 511 whose body reads clean is still a portal (exit $rc)"
              [ "$(cat "$work/out")" = "http://203.0.113.10" ] ||
                fail "a 511 with no link must fall back to the answering address"
            )

            # The scratch file for the probe payload is created after login mode
            # has already released DNS. Unguarded, mktemp's own 1 came back as
            # this script's "no portal", with nothing on screen saying so and the
            # release left standing.
            (
              reset
              tmp_denied="$work/denied-tmp"
              mkdir -p "$tmp_denied"
              chmod 500 "$tmp_denied"
              rc=$(TMPDIR="$tmp_denied" run --no-open)
              chmod 700 "$tmp_denied"
              [ "$rc" -eq 4 ] || fail "a scratch file that cannot be created must exit 4 (exit $rc)"
              released || fail "login mode releases DNS before the probe runs"
              restored || fail "a failed scratch file must not strand the release"
              grep -q '^captive-portal: could not create a scratch file' "$work/err" ||
                fail "the run must say the scratch file could not be created"
            )

            # A 30x with no Location is no answer at all: the canary falls through
            # to the hijack check rather than counting as a detection.
            (
              reset
              export DIG_FIREFOX=192.168.1.99
              export FF_STATUS=302 FF_REDIRECT=""
              export AP_STATUS=000 GS_STATUS=000
              rc=$(run --probe)
              [ "$rc" -eq 0 ] || fail "a private answer behind a bare 30x is a hijack (exit $rc)"
              [ "$(cat "$work/out")" = "http://192.168.1.99" ] ||
                fail "the hijacked address must be the portal URL"
            )

            # /etc/resolv.conf does not exist in the sandbox, which is also what a
            # portal that hands out no lease produces. The unguarded grep aborted
            # the run there; the message is what proves the guard is still in place.
            (
              reset
              rc=$(run --restore)
              [ "$rc" -eq 0 ] || fail "--restore must survive a missing resolv.conf (exit $rc)"
              grep -q 'carries no nameserver line' "$work/err" ||
                fail "a resolv.conf with no nameserver must be reported, not fatal"
            )

            # nmcli's own exit codes are not this script's. Under pipefail the
            # unguarded assignment ended the run with nmcli's 8 and no output at
            # all: no note, no usage, nothing, past a table that stops at 4.
            (
              reset
              rc=$(NM_FAIL=8 run --probe)
              [ "$rc" -eq 4 ] || fail "a failed device listing must exit 4, not leak nmcli's status (exit $rc)"
              grep -q '^captive-portal: NetworkManager is not running' "$work/err" ||
                fail "nmcli's exit 8 must be reported as the daemon being down"
              ! released || fail "a run that could not list devices must not release DNS"
            )

            # Any other nmcli failure is named by its status rather than guessed
            # at, and must not read as the daemon being down.
            (
              reset
              rc=$(NM_FAIL=2 run --probe)
              [ "$rc" -eq 4 ] || fail "an unknown nmcli failure must exit 4 (exit $rc)"
              grep -q '^captive-portal: nmcli could not list devices (exit 2)' "$work/err" ||
                fail "an unknown nmcli failure must name its status"
            )

            # The companion: nmcli answers and nothing is connected. That is the
            # case the two above have to stay distinguishable from.
            (
              reset
              export NM_DEVICES=""
              rc=$(run --probe)
              [ "$rc" -eq 4 ] || fail "zero connected devices must exit 4 (exit $rc)"
              grep -qxF 'captive-portal: no connected wifi or ethernet device' "$work/err" ||
                fail "an empty device list must keep its own wording"
            )

            # The restore worked and then the run crashed on the cleanup: rm's
            # status 1 is this script's "no portal", reported for a --restore
            # that had already handed DNS back.
            (
              reset
              runtime="$work/denied-unlink"
              mkdir -p "$runtime/captive-portal"
              printf 'true\ttrue\n' >"$runtime/captive-portal/tailscale-prefs"
              chmod 555 "$runtime/captive-portal"
              rc=$(XDG_RUNTIME_DIR="$runtime" run --restore)
              chmod 755 "$runtime/captive-portal"
              [ "$rc" -eq 0 ] || fail "a snapshot that cannot be unlinked must not fail the restore (exit $rc)"
              restored || fail "the restore itself must still happen"
              grep -q '^captive-portal: could not remove' "$work/err" ||
                fail "a snapshot left behind must be reported, since the next run replays it"
            )

            # A --device name nmcli does not know reached the resolver guard as
            # "no resolver", so the run sent the user to check a DHCP lease for
            # an interface that is not there. The hosts disagree on the wireless
            # NIC's name, so that is the typo --device invites.
            (
              reset
              rc=$(NM_SHOW_FAIL=10 run --probe --device wlan0)
              [ "$rc" -eq 4 ] || fail "an unknown device must exit 4 (exit $rc)"
              grep -q '^captive-portal: nmcli knows no device named wlan0' "$work/err" ||
                fail "an unknown device must be named as unknown, not as leaseless"
            )

            # The companion, which the wording above has to stay distinct from:
            # the device is real and simply has no resolver yet.
            (
              reset
              export NM_DNS=""
              rc=$(run --probe)
              [ "$rc" -eq 4 ] || fail "a device with no resolver must exit 4 (exit $rc)"
              grep -q 'is the lease up' "$work/err" ||
                fail "a device that exists but has no resolver must keep its own wording"
            )

            # A docked laptop holds two links, and only one can be behind the
            # portal. The pick used to follow nmcli's listing order.
            (
              reset
              export NM_DEVICES='eth0:ethernet:connected\nwifi0:wifi:connected'
              rc=$(run --probe)
              [ "$rc" -eq 1 ] || fail "two connected devices must still probe (exit $rc)"
              grep -q 'device wifi0,' "$work/err" || fail "wifi must win over ethernet"
              grep -q 'also connected: eth0' "$work/err" ||
                fail "the devices passed over must be named"
            )

            touch "$out"
          '';
    };
}
