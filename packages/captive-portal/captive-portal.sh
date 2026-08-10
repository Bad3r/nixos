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
nmcli_status=0
dns_status=0

# sudo-rs enforces env_reset with no opt-out and modules/hosts/common/sudo.nix
# keeps only SSH_AUTH_SOCK, so XDG_RUNTIME_DIR is gone under sudo. Falling back
# to root's own /run/user/0 there put a `sudo captive-portal` snapshot somewhere
# a later plain --restore never looked, and that run then treated a released host
# as one that had never been touched. SUDO_UID survives the reset, so both sides
# name one directory. It is trusted only where logind has already made that
# directory: inventing a runtime root for a user with no session is not a job
# this script should take on, and a user with no session has no browser either.
runtime_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$runtime_dir" ] && [ -n "${SUDO_UID:-}" ] && [ -d "/run/user/$SUDO_UID" ]; then
  runtime_dir="/run/user/$SUDO_UID"
fi
state_dir="${runtime_dir:-/run/user/$(id -u)}/captive-portal"
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

# nmcli runs on its own because the trailing `|| true` has to stay: grep exits 1
# on a device that simply has no DNS, which is not a failure. That `|| true`
# swallowed the whole pipeline though, and pipefail would hand back grep's 1
# ahead of nmcli's own status anyway, so "no device by that name" (exit 10)
# arrived at the caller as "no resolver".
device_dns() {
  local raw
  raw="$(nmcli -t -f IP4.DNS device show "$1")" || return "$?"
  printf '%s\n' "$raw" |
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

# Loopback is deliberately absent: 127.0.0.0/8 is this machine, not somewhere a
# portal can sit. A resolver that sinkholes blocklisted names to 127.0.0.1, which
# is what dnsmasq `address=/host/127.0.0.1` and OpenWrt's simple-adblock do,
# answers a canary that way, and counting it as a hijack pointed the sign-in
# instructions and xdg-open at the user's own machine.
is_private_v4() {
  case "$1" in
  10.* | 192.168.*) return 0 ;;
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
# probe was inconclusive and prints a gateway guess when there is one. Each
# payload lands in $body_file, which the caller owns; see the call site.
probe_portal() {
  local resolver="$1" gateway="$2"
  local hosts urls expects i host url expect answer status redirect found write_out
  local clean=0 host_clean=0

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

    host_clean=0
    status=000
    redirect=""
    # curl truncates -o for any transfer that completes, empty body included, but
    # writes nothing at all when one dies before the first body byte. Clearing it
    # here keeps a canary from being classified against the page the last one
    # fetched, without resting that on curl's file handling.
    : >"$body_file"
    # curl writes its -w line and only then exits nonzero, and that line carries
    # no terminator, so `|| echo '000 '` used to concatenate onto it rather than
    # replace it: `read` took curl's own http_code as the status and the
    # fallback's text as the redirect. A 302 whose body never arrived was
    # reported as a portal at http://<target>000, and one with no Location at
    # http://000. A transfer that failed is not an answer, so whatever it managed
    # to print is dropped and status stays 000, which no arm below matches and
    # which falls through to the hijack check the way a silent drop does.
    # --noproxy '*' because --resolve is the whole basis of the classification
    # here: it is what makes a status and a body attributable to the address the
    # access point's resolver handed back. An inherited http_proxy sends the
    # request to the proxy instead, --resolve never applies, and every canary is
    # then graded on what the proxy answered while dig stays honest.
    # --max-filesize because -m caps time and not bytes, and this body is the one
    # value from the network with no ceiling otherwise: /tmp is disk-backed here
    # (modules/hosts/common/tmp.nix), so a hostile portal could fill the root
    # filesystem with whatever it pushes in six seconds across three canaries,
    # and wc and grep then read all of it. curl exits 63 on the cap, verified
    # against 8.21.0 both with a Content-Length and mid-transfer without one, so
    # this composes with the classification: the guard below fails, status stays
    # 000, and the canary falls through like any other failed transfer.
    if write_out="$(curl -sS -m 6 --max-filesize 1048576 --noproxy '*' -o "$body_file" \
      -w '%{http_code} %{redirect_url}' \
      --resolve "$host:80:$answer" "$url" 2>/dev/null)"; then
      read -r status redirect <<<"$write_out"
    fi

    case "$status" in
    30*)
      # This value is whatever an untrusted network put in Location, and it ends
      # up at xdg-open. curl builds %{redirect_url} through FOLLOW_FAKE, which
      # skips the protocol check it applies when -L actually follows the hop, so
      # `Location: file:///home/user/.ssh/id_ed25519` arrives here intact, as
      # does any scheme with a desktop handler. Only the two the body-extraction
      # path already restricts itself to count; anything else is no answer and
      # falls through to the hijack check below.
      case "$redirect" in
      http://* | https://*)
        printf '%s\n' "$redirect"
        return 0
        ;;
      esac
      ;;
    204)
      # 204 is body-less by definition, so there is nothing left to match.
      host_clean=1
      ;;
    200 | 511)
      # generate_204 carries no expected string because the status is the whole
      # answer: a 200 there is already the portal serving its page inline,
      # which is how an intercepting proxy replies when it does not redirect.
      # 511 is RFC 6585's status for this and reaches the same branch, because a
      # proxy portal that leaves DNS alone answers on the canary's real public
      # address and the status is then the only tell. It is never clean, however
      # its body reads, so only a 200 can clear a canary.
      # The size bound is what makes the marker mean "this canary answered as
      # specified" rather than "the word turns up somewhere". The genuine
      # payloads are 8 and 69 bytes; an interception page is kilobytes, and
      # login pages routinely carry `success:` from a jQuery or hand-rolled AJAX
      # callback, which cleared the canary and had the run hand DNS back on a
      # network that did have a portal. Bounding beats pinning the exact
      # document, which Apple can change out from under this.
      if [ "$status" = 200 ] && [ -n "$expect" ] &&
        [ "$(wc -c <"$body_file")" -le 256 ] && grep -qF "$expect" "$body_file"; then
        host_clean=1
      else
        # The first absolute URL in a page is usually not the sign-in target. An
        # intercepted page served as XHTML opens with the w3.org DTD in its
        # DOCTYPE, and a CDN script tag sits above the form on plenty of others,
        # so matching anywhere in the body opened w3.org or googleapis while the
        # form went unseen. Only what a link, form or meta refresh points at
        # counts, and w3.org is dropped even there, because a "Valid XHTML"
        # badge is the one href some portal pages carry besides a relative form.
        # Finding nothing is the good outcome then: the caller falls back to the
        # address that answered the hijacked lookup, which is at least the host
        # serving the page.
        # Every attribute name is anchored on line start, `;`, or whitespace, so
        # each is the whole attribute rather than the tail of a longer one or a
        # fragment of a query string: unanchored, `data-href=` and `?href=` both
        # matched, and since grep -o emits in positional order a tracker URL
        # ahead of the form won. The anchor still admits `<form action=`,
        # `<a href=`, an attribute at the start of a wrapped line, and a meta
        # refresh's `content="0; url=..."` with or without the space.
        # `formaction` is named because anchoring would otherwise drop it, its
        # `action` being preceded by `m`. The w3.org pattern needs the leading
        # dot optional and the trailing slash relaxed, or `http://w3.org/TR/...`
        # and `http://www.w3.org` walk past it.
        found="$(grep -oiE '(^|[;[:space:]])(formaction|href|action|url)=["'"'"']?https?://[^"'"'"'<>[:space:]]+' "$body_file" |
          grep -oiE 'https?://[^"'"'"'<>[:space:]]+' |
          grep -viE '^https?://([^/]*\.)?w3\.org([/:?]|$)' | head -1 || true)"
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

# Root wrote the snapshot into the invoking user's runtime directory, so it has
# to change hands with it: a plain --restore can read a root-owned snapshot but
# not unlink it, and rm -f reports that EACCES rather than swallowing it.
hand_state_to_invoker() {
  if [ "$(id -u)" -ne 0 ] || [ -z "${SUDO_UID:-}" ]; then
    return 0
  fi
  chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$state_dir" "$state_file" ||
    note "the snapshot stays owned by root; run the restore under sudo too: sudo captive-portal --restore"
}

# The snapshot must survive a retry: a second login run after a failed sign-in
# would otherwise record the already-released prefs as the originals, and
# --restore would then replay --accept-dns=false as if that were the user's
# state. The first snapshot of a session wins until --restore consumes it.
save_prefs() {
  local prefs tmp=""
  # Every step is checked because `if ! save_prefs` is the only call site, and
  # that suspends errexit for the whole body: an unchecked failure fell through
  # to the trailing assignment and reported success, so the run went on to
  # release DNS with nothing recorded to put back.
  if ! mkdir -p "$state_dir"; then
    note "cannot create $state_dir; leaving DNS untouched"
    return 1
  fi
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
  if ! tmp="$(mktemp "$state_file.XXXXXX")" ||
    ! printf '%s\n' "$prefs" >"$tmp" ||
    ! mv "$tmp" "$state_file"; then
    if [ -n "$tmp" ]; then
      rm -f "$tmp"
    fi
    note "cannot write $state_file; leaving DNS untouched"
    return 1
  fi
  hand_state_to_invoker
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
    # Guarded for the same reason as the unlink in restore_dns: a bare rm that
    # fails exits 1, which this script documents as "no portal", and errexit
    # would end the run there rather than at the exit 4 below, reporting a
    # tailscaled refusal as a clean network.
    if [ "$prefs_snapshot_created" -eq 1 ] && ! rm -f "$state_file"; then
      note "could not remove $state_file; delete it, or the next run will replay it"
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

# The two halves fail for unrelated reasons and need unrelated remedies, so they
# report separately: 1 is the DNS write, which is the call the operator pref
# gates, and 2 is the run state, which is only ever reached once DNS is back.

# `debug prefs` answering is no promise the field is there, and jq's -e turns an
# absent or non-boolean one into a nonzero status rather than an empty string.
read_want_running() {
  tailscale debug prefs |
    jq -er 'if (.WantRunning | type) == "boolean" then (.WantRunning | tostring)
            else error("WantRunning missing") end'
}

apply_saved_prefs() {
  local corp_dns="$1" want_running="$2" live_running=""
  # DNS is what the run took away, so it goes back first. Ordering the run state
  # ahead of it let a refused `up` keep the resolvers off a host that could have
  # had them back.
  if [ "$corp_dns" = "true" ]; then
    tailscale set --accept-dns=true || return 1
  fi
  # A flagless `tailscale up` on a node that is still logged in edits WantRunning
  # alone, so it cannot clobber the prefs this two-field snapshot does not carry:
  # checkForAccidentalSettingReverts in cmd/tailscale/cli/up.go returns simpleUp
  # when no flag is set, skipping the pref diff that produces `flag --ssh is not
  # specified but it is set in prefs`. It runs only when the snapshot says --down
  # stopped a node that had been up.
  if [ "$want_running" = "true" ]; then
    # A failed read used to land here as an empty string, compare unequal to
    # false, and skip the restart the snapshot had just asked for without saying
    # anything. Not knowing the run state is a reason to stop, not to guess.
    if ! live_running="$(read_want_running)"; then
      note "cannot read Tailscale prefs, so whether the node needs starting is unknown"
      return 2
    fi
    if [ "$live_running" = "false" ] && ! tailscale up; then
      note "tailscaled refused 'tailscale up'"
      return 2
    fi
  fi
}

restore_dns() {
  local corp_dns=true want_running=false saved_corp="" saved_want="" rc=0 dns_outcome=""
  # An unreadable or truncated state file must not abort the run and must not
  # decide that DNS stays off, so CorpDNS falls back to restoring Tailscale DNS.
  # WantRunning gets no such fallback: with no snapshot there is no evidence the
  # node was ever up, and starting one the user stopped is not a restore.
  if [ -s "$state_file" ] && read -r saved_corp saved_want <"$state_file"; then
    case "$saved_corp" in true | false) corp_dns="$saved_corp" ;; esac
    case "$saved_want" in true | false) want_running="$saved_want" ;; esac
  fi
  apply_saved_prefs "$corp_dns" "$want_running" || rc=$?
  if [ "$rc" -eq 1 ]; then
    denied
    # The snapshot is what a later run replays, so a refusal keeps it: dropping
    # it here would turn a retryable failure into a permanently released host.
    note "DNS is still released; rerun once that is fixed: captive-portal --restore"
    exit 4
  fi
  # The DNS half is settled from here on, whether that meant handing it back or
  # leaving it as the snapshot found it, so the reload it needs still has to run
  # and the interrupt reminder has to stand down.
  reload_nm_dns
  dns_released=0
  # apply_saved_prefs skips the DNS write for a saved false, correctly, since
  # that was the host's state. Reporting it as handed back anyway told the user
  # the release was undone on the one run where it deliberately was not, and this
  # is the line they read to decide exactly that.
  if [ "$corp_dns" = "true" ]; then
    dns_outcome="DNS returned to Tailscale"
  else
    dns_outcome="the snapshot recorded Tailscale DNS as already off, so it was left off"
  fi
  if [ "$rc" -ne 0 ]; then
    # Not the operator wall: that gate had already passed the DNS write above,
    # and apply_saved_prefs has already named which half of the run state failed.
    # The snapshot stays because it is the only record that this node was up.
    note "$dns_outcome"
    note "the node's run state was not restored; start it with 'tailscale up', or rerun: captive-portal --restore"
    exit 4
  fi
  # save_prefs keeps the first snapshot of a session, so one left behind here is
  # replayed by the next run as prefs the host may no longer hold. The restore
  # itself succeeded, so this is reported the way a failed reload is: unguarded,
  # it crashed the run with rm's status 1, which for this script means "no
  # portal", after the restore it is reporting had already worked.
  if ! rm -f "$state_file"; then
    note "could not remove $state_file; delete it, or the next run will replay it"
  fi
  note "$dns_outcome"
  show_resolvers
}

if [ "$mode" = restore ]; then
  restore_dns
  exit 0
fi

candidates=""
if [ -z "$device" ]; then
  candidates="$(candidate_devices)" || nmcli_status=$?
  device="$(printf '%s\n' "$candidates" | head -1 | cut -d: -f2)"
fi
if [ -z "$device" ]; then
  # nmcli's exit codes are not this script's. Unguarded, and under pipefail, the
  # assignment above ended the run with nmcli's own 8 and printed nothing at
  # all, past a status table that stops at 4 and past this guard.
  case "$nmcli_status" in
  0) note "no connected wifi or ethernet device" ;;
  8) note "NetworkManager is not running, so nmcli could not list devices" ;;
  *) note "nmcli could not list devices (exit $nmcli_status)" ;;
  esac
  exit 4
fi

# Only one of several connected devices can be behind the portal, and nothing
# here can tell which, so name the ones that were passed over.
others="$(printf '%s\n' "$candidates" | tail -n +2 | cut -d: -f2 | paste -sd' ' - || true)"
if [ -n "$others" ]; then
  note "also connected: $others; pass --device to inspect one of those"
fi

resolver="$(device_dns "$device" | head -1)" || dns_status=$?
gateway="$(device_gateway "$device")"
if [ -z "$resolver" ]; then
  # --device is checked for shape and never for existence, and the hosts do not
  # agree on what the wireless NIC is called (modules/tpnix/networking.nix pins
  # wifi0 where system76 keeps wlan0), so a name from the wrong host is the typo
  # the flag invites. Sending that to check a DHCP lease names an interface that
  # is not there.
  case "$dns_status" in
  0) note "$device has no DHCP-provided resolver; is the lease up?" ;;
  10) note "nmcli knows no device named $device; pick one from: nmcli -t -f DEVICE device status" ;;
  *) note "nmcli could not read the DNS of $device (exit $dns_status)" ;;
  esac
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
# The scratch file is created here rather than in probe_portal because the
# function only ever runs inside a command substitution: bash does not fire the
# parent's EXIT trap in that subshell, and an assignment made there cannot escape
# it, so a body_file created inside was invisible to cleanup and every run left
# the page it had fetched behind. Created in the shell that owns the trap, the
# sweep already written above covers it on every exit and on a signal.
if ! body_file="$(mktemp)"; then
  # Unguarded, mktemp's own 1 came back as this script's "no portal", from a
  # point login mode has already released DNS: errexit killed the run with
  # mktemp's error the only thing on screen, no reminder, and no restore.
  note "could not create a scratch file for the probe payload"
  if [ "$mode" = login ]; then
    restore_dns
  fi
  exit 4
fi
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
