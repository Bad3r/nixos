# shellcheck shell=bash
# Reach a captive portal from a host that resolves through Tailscale.
#
# With --accept-dns=true tailscaled registers a resolvconf entry that supersedes
# NetworkManager's, so the dnsmasq at 127.0.0.1 is shadowed and every query goes
# to the tailnet's global resolvers. A portal drops those upstreams
# until you authenticate and answers only on its own DHCP-advertised resolver, so
# the DNS hijack that produces the sign-in page never runs and nothing surfaces
# the portal. This releases DNS back to dnsmasq, finds the portal through the
# access point's own resolver, and opens it.

set -euo pipefail

mode=login
device=""
open_browser=1
stop_tailscale=0

state_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/captive-portal"
state_file="$state_dir/tailscale-prefs"

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
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --device)
    device="${2:-}"
    [ -n "$device" ] || {
      echo "captive-portal: --device needs a value" >&2
      exit 2
    }
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

pick_device() {
  nmcli -t -f DEVICE,TYPE,STATE device status |
    awk -F: '$3 == "connected" && ($2 == "wifi" || $2 == "ethernet") { print $1; exit }'
}

device_dns() {
  nmcli -t -f IP4.DNS device show "$1" |
    sed 's/^IP4\.DNS\[[0-9]*\]:*//' |
    grep -E '^[0-9]+(\.[0-9]+){3}$' || true
}

device_gateway() {
  ip -4 route show default dev "$1" | awk '{ print $3; exit }'
}

is_private_v4() {
  case "$1" in
  10.* | 192.168.* | 127.*) return 0 ;;
  172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
  *) return 1 ;;
  esac
}

# A portal that hijacks DNS answers public names with an address it controls, and
# one that intercepts HTTP replaces the probe payload or 302s away from it. Both
# reveal the sign-in URL. Exit 0 prints the portal URL, 1 means the network came
# back clean, 2 means every probe was inconclusive and prints a gateway guess.
probe_portal() {
  local resolver="$1" gateway="$2"
  local hosts urls expects i host url expect answer status redirect body found
  local clean=0

  hosts=(detectportal.firefox.com captive.apple.com connectivity-check.gstatic.com)
  urls=(
    http://detectportal.firefox.com/success.txt
    http://captive.apple.com/hotspot-detect.html
    http://connectivity-check.gstatic.com/generate_204
  )
  expects=(success Success "")

  for i in "${!hosts[@]}"; do
    host="${hosts[$i]}"
    url="${urls[$i]}"
    expect="${expects[$i]}"

    answer="$(dig +short +time=2 +tries=1 "@$resolver" A "$host" |
      grep -E '^[0-9]+(\.[0-9]+){3}$' | tail -1 || true)"
    [ -n "$answer" ] || continue

    body="$(mktemp)"
    status=000
    redirect=""
    read -r status redirect <<<"$(
      curl -sS -m 6 -o "$body" -w '%{http_code} %{redirect_url}' \
        --resolve "$host:80:$answer" "$url" 2>/dev/null || echo '000 '
    )"

    case "$status" in
    30*)
      [ -n "$redirect" ] && {
        printf '%s\n' "$redirect"
        rm -f "$body"
        return 0
      }
      ;;
    200 | 204)
      if [ -n "$expect" ] && ! grep -qF "$expect" "$body"; then
        found="$(grep -oiE 'https?://[^"'"'"'<>[:space:]]+' "$body" | head -1 || true)"
        printf '%s\n' "${found:-http://$answer}"
        rm -f "$body"
        return 0
      fi
      clean=1
      ;;
    esac
    rm -f "$body"

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
  return 2
}

save_prefs() {
  mkdir -p "$state_dir"
  tailscale debug prefs | jq -r '[.CorpDNS, .WantRunning] | @tsv' >"$state_file"
}

release_dns() {
  save_prefs
  if [ "$stop_tailscale" -eq 1 ]; then
    tailscale down
  else
    tailscale set --accept-dns=false
  fi
  # dnsmasq holds the tailnet upstreams and any cached SERVFAIL until NM re-applies DNS.
  nmcli general reload dns-full
}

restore_dns() {
  local corp_dns=true want_running=true
  if [ -f "$state_file" ]; then
    read -r corp_dns want_running <"$state_file"
  fi
  # `tailscale up` resets every pref it is not passed, so reach for it only when
  # --down stopped a node that had been running.
  if [ "$want_running" = "true" ] && [ "$(tailscale debug prefs | jq -r '.WantRunning')" = "false" ]; then
    tailscale up
  fi
  if [ "$corp_dns" = "true" ]; then
    tailscale set --accept-dns=true
  fi
  rm -f "$state_file"
  nmcli general reload dns-full
  echo "captive-portal: DNS returned to Tailscale"
  grep '^nameserver' /etc/resolv.conf
}

if [ "$mode" = restore ]; then
  restore_dns
  exit 0
fi

[ -n "$device" ] || device="$(pick_device)"
if [ -z "$device" ]; then
  echo "captive-portal: no connected wifi or ethernet device" >&2
  exit 1
fi

resolver="$(device_dns "$device" | head -1)"
gateway="$(device_gateway "$device")"
if [ -z "$resolver" ]; then
  echo "captive-portal: $device has no DHCP-provided resolver; is the lease up?" >&2
  exit 1
fi

echo "captive-portal: device $device, access-point resolver $resolver, gateway ${gateway:-unknown}"

if [ "$mode" = login ]; then
  release_dns
  echo "captive-portal: system resolvers now:"
  grep '^nameserver' /etc/resolv.conf
fi

portal=""
probe_status=0
portal="$(probe_portal "$resolver" "$gateway")" || probe_status=$?

case "$probe_status" in
1)
  echo "captive-portal: no portal detected; this network answers probes normally"
  if [ "$mode" = login ]; then
    restore_dns
  fi
  exit 0
  ;;
2)
  if [ -z "$portal" ]; then
    echo "captive-portal: probes inconclusive and no gateway to fall back on" >&2
    exit 1
  fi
  echo "captive-portal: probes inconclusive; falling back to the gateway"
  ;;
esac

echo "captive-portal: portal at $portal"

if [ "$mode" = probe ]; then
  exit 0
fi

if [ "$open_browser" -eq 1 ]; then
  # LibreWolf ships network.captive-portal-service.enabled=false, so it never
  # raises a sign-in bar on its own; open the URL directly instead.
  xdg-open "$portal" >/dev/null 2>&1 &
fi

cat <<EOF

Sign in at the page above, then run:

  captive-portal --restore

If the page does not load, open it in a private window: portals reject cached
HSTS upgrades and stale cookies from an earlier session.
EOF
