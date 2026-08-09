# shellcheck shell=bash
# Reach a captive portal from a host that resolves through Tailscale.
#
# With --accept-dns=true tailscaled takes resolution away from whichever local
# resolver the host runs: it registers a resolvconf entry that supersedes
# NetworkManager's dnsmasq at 127.0.0.1, or hands its configuration to
# systemd-resolved where that owns /etc/resolv.conf instead. Either way every
# query goes to the tailnet's global resolvers. A portal drops those upstreams
# until you authenticate and answers only on its own DHCP-advertised resolver, so
# the DNS hijack that produces the sign-in page never runs and nothing surfaces
# the portal. This releases DNS back to the local resolver, finds the portal
# through the access point's own resolver, and opens it.

set -euo pipefail

mode=login
device=""
open_browser=1
stop_tailscale=0
dns_released=0
prefs_snapshot_created=0

state_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/captive-portal"
state_file="$state_dir/tailscale-prefs"

body_file=""

# shellcheck disable=SC2329  # invoked through the traps below
cleanup() {
  if [ -n "$body_file" ]; then
    rm -f "$body_file"
  fi
}
trap cleanup EXIT

# Probing three canaries takes up to ~24s, so a Ctrl-C inside that window is
# likely. Bash's default disposition would drop the user back to the shell with
# Tailscale DNS still off and nothing on screen saying so.
# shellcheck disable=SC2329  # invoked through the INT and TERM traps below
on_signal() {
  trap - INT TERM
  cleanup
  if [ "$dns_released" -eq 1 ]; then
    printf '\n' >&2
    note "interrupted with DNS still released; run: captive-portal --restore"
  fi
  kill -s "$1" "$$"
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

usage() {
  cat <<'EOF'
Usage:
  captive-portal [--device DEV] [--no-open] [--down]
      Release DNS to the local network, locate the portal, and open it.
  captive-portal --probe [--device DEV]
      Report portal state and URL without touching DNS.
  captive-portal --restore
      Return DNS to Tailscale after signing in.

Options:
  --device DEV  Device to inspect (default: first connected wifi/ethernet).
  --no-open     Print the portal URL instead of launching a browser.
  --down        Stop Tailscale entirely rather than only releasing DNS.

Only the portal URL goes to stdout; everything else is written to stderr.

Exit status:
  0  a portal was found and its URL was printed
  1  no portal: this network answers the probes normally
  2  invalid usage
  3  the probes were inconclusive; a gateway guess is printed, never opened
  4  the network could not be inspected, or Tailscale state could not be read
     or changed

Changing DNS needs write access to tailscaled, which answers only root and the
Unix user named by its operator pref. --probe reads the access point's resolver
directly and needs neither.
EOF
}

note() {
  printf 'captive-portal: %s\n' "$*" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --device)
    device="${2:-}"
    # `--device --probe` used to consume the flag as a device name and then run
    # in login mode, releasing real DNS for a request that asked to change none.
    case "$device" in
    "" | -*)
      echo "captive-portal: --device needs a device name, got '${device:-}'" >&2
      exit 2
      ;;
    esac
    shift 2
    ;;
  --probe)
    mode=probe
    shift
    ;;
  --restore)
    mode=restore
    shift
    ;;
  --no-open)
    open_browser=0
    shift
    ;;
  --down)
    stop_tailscale=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "captive-portal: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

# Portals live on the wireless hop, so a docked laptop holding both links must
# not have the choice decided by nmcli's listing order. Sorting the wifi-first
# key makes the pick reproducible, and the caller reports the runners-up.
candidate_devices() {
  nmcli -t -f DEVICE,TYPE,STATE device status |
    awk -F: '$3 == "connected" && ($2 == "wifi" || $2 == "ethernet") {
      print ($2 == "wifi" ? 0 : 1) ":" $1
    }' |
    sort
}

device_dns() {
  nmcli -t -f IP4.DNS device show "$1" |
    sed 's/^IP4\.DNS\[[0-9]*\]:*//' |
    grep -E '^[0-9]+(\.[0-9]+){3}$' || true
}

# An on-link default route ("default dev wlan0 scope link", which tethered and
# point-to-point links produce) carries no via, and $3 is then the device name:
# taking it verbatim yielded a portal URL of http://wlan0.
device_gateway() {
  ip -4 route show default dev "$1" |
    awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }' |
    grep -E '^[0-9]+(\.[0-9]+){3}$' || true
}

is_private_v4() {
  case "$1" in
  10.* | 192.168.* | 127.*) return 0 ;;
  172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
  # A portal answers from whatever space it sits in: 169.254.0.0/16 when it
  # never issued a lease, and 100.64.0.0/10 on carrier and guest networks.
  169.254.*) return 0 ;;
  100.6[4-9].* | 100.[7-9][0-9].* | 100.1[01][0-9].* | 100.12[0-7].*) return 0 ;;
  *) return 1 ;;
  esac
}

# A portal that hijacks DNS answers public names with an address it controls, and
# one that intercepts HTTP replaces the probe payload or 302s away from it. Both
# reveal the sign-in URL. The return values are the script's own exit statuses:
# 0 prints the portal URL, 1 means the network came back clean, 3 means every
# probe was inconclusive and prints a gateway guess when there is one.
probe_portal() {
  local resolver="$1" gateway="$2"
  local hosts urls expects i host url expect answer status redirect found
  local clean=0 host_clean=0

  hosts=(detectportal.firefox.com captive.apple.com connectivity-check.gstatic.com)
  urls=(
    http://detectportal.firefox.com/success.txt
    http://captive.apple.com/hotspot-detect.html
    http://connectivity-check.gstatic.com/generate_204
  )
  expects=(success Success "")

  body_file="$(mktemp)"

  for i in "${!hosts[@]}"; do
    host="${hosts[$i]}"
    url="${urls[$i]}"
    expect="${expects[$i]}"

    answer="$(dig +short +time=2 +tries=1 "@$resolver" A "$host" |
      grep -E '^[0-9]+(\.[0-9]+){3}$' | tail -1 || true)"
    [ -n "$answer" ] || continue

    host_clean=0
    status=000
    redirect=""
    read -r status redirect <<<"$(
      curl -sS -m 6 -o "$body_file" -w '%{http_code} %{redirect_url}' \
        --resolve "$host:80:$answer" "$url" 2>/dev/null || echo '000 '
    )"

    case "$status" in
    30*)
      if [ -n "$redirect" ]; then
        printf '%s\n' "$redirect"
        return 0
      fi
      ;;
    204)
      # 204 is body-less by definition, so there is nothing left to match.
      host_clean=1
      ;;
    200)
      # generate_204 carries no expected string because the status is the whole
      # answer: a 200 there is already the portal serving its page inline,
      # which is how an intercepting proxy replies when it does not redirect.
      if [ -n "$expect" ] && grep -qF "$expect" "$body_file"; then
        host_clean=1
      else
        found="$(grep -oiE 'https?://[^"'"'"'<>[:space:]]+' "$body_file" | head -1 || true)"
        printf '%s\n' "${found:-http://$answer}"
        return 0
      fi
      ;;
    esac

    if [ "$host_clean" -eq 1 ]; then
      # This canary answered as specified, so the address it resolved to is not
      # a hijack however private it looks, and the check below must not run.
      clean=1
      continue
    fi

    # The probe host answered with an address on this LAN: a DNS hijack.
    if is_private_v4 "$answer"; then
      printf 'http://%s\n' "$answer"
      return 0
    fi
  done

  [ "$clean" -eq 1 ] && return 1
  if [ -n "$gateway" ]; then
    printf 'http://%s\n' "$gateway"
  fi
  return 3
}

# The snapshot must survive a retry: a second login run after a failed sign-in
# would otherwise record the already-released prefs as the originals, and
# --restore would then replay --accept-dns=false as if that were the user's
# state. The first snapshot of a session wins until --restore consumes it.
save_prefs() {
  local prefs tmp
  mkdir -p "$state_dir"
  if [ -s "$state_file" ]; then
    return 0
  fi
  if ! prefs="$(tailscale debug prefs |
    jq -er '[.CorpDNS, .WantRunning] |
      if all(type == "boolean") then @tsv else error("CorpDNS/WantRunning missing") end')"; then
    note "cannot read Tailscale prefs; leaving DNS untouched"
    return 1
  fi
  # Write through a temporary so a failed read never leaves a truncated file
  # that --restore would later parse as "DNS was already off".
  tmp="$(mktemp "$state_file.XXXXXX")"
  printf '%s\n' "$prefs" >"$tmp"
  mv "$tmp" "$state_file"
  prefs_snapshot_created=1
}

# tailscaled answers `debug prefs` for anyone but takes a state change only from
# root and from the Unix user named by its operator pref, so reading the prefs
# proves nothing about being allowed to change them. Every caller below acts on
# the refusal itself rather than second-guessing that rule.
denied() {
  note "tailscaled refused the change: it accepts one only from root or its operator user"
  note "run this under sudo, or set programs.tailscale.extended.operator to $(id -un)"
}

drop_dns() {
  if [ "$stop_tailscale" -eq 1 ]; then
    tailscale down
  else
    tailscale set --accept-dns=false
  fi
}

# dnsmasq holds the tailnet upstreams and any cached SERVFAIL until NM re-applies
# DNS. A reload that fails leaves stale resolvers behind rather than a wrong
# Tailscale state, so it is reported and the run carries on.
reload_nm_dns() {
  if ! nmcli general reload dns-full; then
    note "NetworkManager did not reload DNS; run: nmcli general reload dns-full"
  fi
}

release_dns() {
  if ! save_prefs; then
    exit 4
  fi
  dns_released=1
  if ! drop_dns; then
    # Nothing was released, so the reminders must not fire and the snapshot this
    # run took must not outlive it and be replayed as a state the host never left.
    dns_released=0
    denied
    if [ "$prefs_snapshot_created" -eq 1 ]; then
      rm -f "$state_file"
    fi
    exit 4
  fi
  reload_nm_dns
}

# /etc/resolv.conf legitimately carries no nameserver before a portal hands out
# a lease, and on a systemd-resolved host it only ever carries the 127.0.0.53
# stub, so neither case may abort the run or masquerade as the whole story.
show_resolvers() {
  local lines
  lines="$(grep '^nameserver' /etc/resolv.conf || true)"
  if [ -z "$lines" ]; then
    note "/etc/resolv.conf carries no nameserver line"
    return 0
  fi
  printf '%s\n' "$lines" >&2
  if ! printf '%s\n' "$lines" | grep -qvE '^nameserver[[:space:]]+127\.'; then
    note "that is a local stub; its upstream is the active connection's DNS"
  fi
}

apply_saved_prefs() {
  local corp_dns="$1" want_running="$2"
  # DNS is what the run took away, so it goes back first. Ordering the run state
  # ahead of it let a refused `up` keep the resolvers off a host that could have
  # had them back.
  if [ "$corp_dns" = "true" ]; then
    tailscale set --accept-dns=true || return 1
  fi
  # A flagless `tailscale up` on a node that is still logged in edits WantRunning
  # alone, so it cannot clobber the prefs this two-field snapshot does not carry.
  # It runs only when the snapshot says --down stopped a node that had been up.
  if [ "$want_running" = "true" ] && [ "$(tailscale debug prefs | jq -r '.WantRunning')" = "false" ]; then
    tailscale up || return 1
  fi
}

restore_dns() {
  local corp_dns=true want_running=false saved_corp="" saved_want=""
  # An unreadable or truncated state file must not abort the run and must not
  # decide that DNS stays off, so CorpDNS falls back to restoring Tailscale DNS.
  # WantRunning gets no such fallback: with no snapshot there is no evidence the
  # node was ever up, and starting one the user stopped is not a restore.
  if [ -s "$state_file" ] && read -r saved_corp saved_want <"$state_file"; then
    case "$saved_corp" in true | false) corp_dns="$saved_corp" ;; esac
    case "$saved_want" in true | false) want_running="$saved_want" ;; esac
  fi
  if ! apply_saved_prefs "$corp_dns" "$want_running"; then
    denied
    # The snapshot is what a later run replays, so a refusal keeps it: dropping
    # it here would turn a retryable failure into a permanently released host.
    note "DNS is still released; rerun once that is fixed: captive-portal --restore"
    exit 4
  fi
  rm -f "$state_file"
  reload_nm_dns
  dns_released=0
  note "DNS returned to Tailscale"
  show_resolvers
}

if [ "$mode" = restore ]; then
  restore_dns
  exit 0
fi

candidates=""
if [ -z "$device" ]; then
  candidates="$(candidate_devices)"
  device="$(printf '%s\n' "$candidates" | head -1 | cut -d: -f2)"
fi
if [ -z "$device" ]; then
  note "no connected wifi or ethernet device"
  exit 4
fi

# Only one of several connected devices can be behind the portal, and nothing
# here can tell which, so name the ones that were passed over.
others="$(printf '%s\n' "$candidates" | tail -n +2 | cut -d: -f2 | paste -sd' ' - || true)"
if [ -n "$others" ]; then
  note "also connected: $others; pass --device to inspect one of those"
fi

resolver="$(device_dns "$device" | head -1)"
gateway="$(device_gateway "$device")"
if [ -z "$resolver" ]; then
  note "$device has no DHCP-provided resolver; is the lease up?"
  exit 4
fi

note "device $device, access-point resolver $resolver, gateway ${gateway:-unknown}"

if [ "$mode" = login ]; then
  release_dns
  note "system resolvers now:"
  show_resolvers
fi

portal=""
probe_status=0
portal="$(probe_portal "$resolver" "$gateway")" || probe_status=$?

# Every exit from here on is one of the documented statuses, and each one that
# leaves login mode has to decide what happens to the DNS release.
case "$probe_status" in
1)
  note "no portal detected; this network answers probes normally"
  if [ "$mode" = login ]; then
    restore_dns
  fi
  exit 1
  ;;
3)
  if [ -z "$portal" ]; then
    note "probes inconclusive and no gateway to fall back on"
    # Nothing was found and nothing more will be tried, so the release must not
    # outlive the run the way it did when this path exited on the spot.
    if [ "$mode" = login ]; then
      restore_dns
    fi
    exit 3
  fi
  # This is the gateway, not a portal anything confirmed: on a network that
  # merely blocks the canaries it is the user's own router. Say so rather than
  # reusing the wording of a detection.
  note "probes inconclusive; no portal confirmed. This network's gateway, which may just be your router:"
  ;;
esac

if [ "$probe_status" -eq 0 ]; then
  note "portal at $portal"
fi
printf '%s\n' "$portal"

if [ "$mode" = probe ]; then
  exit "$probe_status"
fi

# Only a confirmed detection earns a browser. The gateway guess is as likely to
# be the user's own router, and opening that unasked is worse than printing it.
if [ "$open_browser" -eq 1 ] && [ "$probe_status" -eq 0 ]; then
  # LibreWolf ships network.captive-portal-service.enabled=false, so it never
  # raises a sign-in bar on its own; open the URL directly instead.
  xdg-open "$portal" >/dev/null 2>&1 &
fi

if [ "$probe_status" -eq 0 ]; then
  cat >&2 <<'EOF'

Sign in at the page above, then run:

  captive-portal --restore

If the page does not load, open it in a private window: portals reject cached
HSTS upgrades and stale cookies from an earlier session.
EOF
else
  cat >&2 <<'EOF'

Nothing was confirmed as a portal, so the address above was not opened. Try it
by hand if you want, in a private window: portals reject cached HSTS upgrades
and stale cookies from an earlier session. DNS stays released until you run:

  captive-portal --restore
EOF
fi

exit "$probe_status"
