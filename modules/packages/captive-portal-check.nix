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
              printf '{"CorpDNS":%s,"WantRunning":%s}\n' \
                "''${TS_CORP_DNS-true}" "''${TS_WANT_RUNNING-true}"
              exit 0
            fi
            printf 'tailscale %s\n' "$*" >>"$CP_LOG"
            case " ''${TS_FAIL_STATE-} " in
            *" $1 "*) exit 1 ;;
            esac
          '';

          nmcliStub = pkgs.writeShellScriptBin "nmcli" ''
            case "$*" in
            *"DEVICE,TYPE,STATE device status")
              printf '%b\n' "''${NM_DEVICES-wifi0:wifi:connected}"
              ;;
            *"IP4.DNS device show"*)
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
            while [ "$#" -gt 0 ]; do
              case "$1" in
              -o)
                out="$2"
                shift 2
                ;;
              http://*)
                url="$1"
                shift
                ;;
              *) shift ;;
              esac
            done
            case "$url" in
            *success.txt)
              status="''${FF_STATUS-200}"
              body="''${FF_BODY-success}"
              redirect="''${FF_REDIRECT-}"
              ;;
            *hotspot-detect.html)
              status="''${AP_STATUS-200}"
              body="''${AP_BODY-<HTML><BODY>Success</BODY></HTML>}"
              redirect="''${AP_REDIRECT-}"
              ;;
            *generate_204)
              status="''${GS_STATUS-204}"
              body="''${GS_BODY-}"
              redirect="''${GS_REDIRECT-}"
              ;;
            *)
              echo "curl stub: unexpected url: $url" >&2
              exit 1
              ;;
            esac
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

            # A canary that answered correctly from a private address. The
            # hijack check used to run anyway and overrule the payload that had
            # just proved there was no interception.
            (
              reset
              export DIG_FIREFOX=192.168.1.50
              rc=$(run --probe)
              [ "$rc" -eq 1 ] || fail "a correct answer from a private address is not a hijack (exit $rc)"
            )

            # 100.64.0.0/10 and 169.254.0.0/16 are where a portal answers on
            # carrier and lease-less networks, and neither counted as private.
            for hijack in 100.100.64.9 169.254.7.7; do
              (
                reset
                export DIG_FIREFOX="$hijack"
                export FF_STATUS=200 FF_BODY='<html>portal</html>'
                export AP_STATUS=000 GS_STATUS=000
                rc=$(run --probe)
                [ "$rc" -eq 0 ] || fail "an answer in $hijack's range is a hijack (exit $rc)"
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
