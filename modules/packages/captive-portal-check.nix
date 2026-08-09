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
  that hands out no lease produces. The login scenarios below therefore cover the
  unguarded `grep '^nameserver' /etc/resolv.conf` that used to abort the run
  between releasing DNS and probing for the portal.
*/
{
  perSystem =
    { pkgs, ... }:
    {
      checks."packages/captive-portal-runtime" =
        let
          # Answers `debug prefs` from the environment and records every state
          # change, so a scenario can assert on what the run did to DNS.
          tailscaleStub = pkgs.writeShellScriptBin "tailscale" ''
            if [ "$*" = "debug prefs" ]; then
              printf '{"CorpDNS":%s,"WantRunning":%s}\n' \
                "''${TS_CORP_DNS-true}" "''${TS_WANT_RUNNING-true}"
              exit 0
            fi
            printf 'tailscale %s\n' "$*" >>"$CP_LOG"
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
