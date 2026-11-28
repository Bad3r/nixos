# shellcheck shell=bash
# vault76: unlock, lock and auto-lock the LUKS2 volume vault76.
# vault76.nix sets VAULT76_UUID, VAULT76_DEFAULT_TIMEOUT (seconds) and
# VAULT76_OWNER, the user whose desktop gets the auto-lock notifications.

mnt=/srv/vault76
mapper=/dev/mapper/vault76
mount_unit=srv-vault76.mount
crypt_unit=systemd-cryptsetup@vault76.service
autolock_unit=vault76-autolock.service
state=/run/vault76
warn_s=60
poll_s=10

usage() {
	cat <<EOF
Usage: sudo vault76 unlock [--timeout=DURATION]
       sudo vault76 lock
       sudo vault76 wipe [--force]
       vault76 status

Commands:
  unlock    Unlock vault76 with a YubiKey or the passphrase and mount it at
            $mnt. On an unlocked vault76 it applies --timeout and restarts
            the idle clock.
  lock      Unmount and lock vault76.
  wipe      Lock vault76, erase its key slots and zero-fill the partition.
            No YubiKey, passphrase or header backup opens its data again.
            It asks to type vault76 first.
  status    Show whether vault76 is unlocked, its timeout and its idle time.

Options:
  -t, --timeout=DURATION
            With unlock: lock after DURATION without a read or write on the
            drive: off, or minutes and hours such as 45m, 1h or 1h30m, at
            least 2m. A notification comes 1m before the lock. The value
            holds until the next lock; the default is $(fmt_duration "$VAULT76_DEFAULT_TIMEOUT").
  -f, --force
            With wipe: erase without asking.
  -h, --help
            Show this help.
EOF
}

die() {
	echo "vault76: $*" >&2
	exit 1
}

fmt_duration() {
	local s=$1
	if [[ $s == off ]]; then
		echo off
	elif ((s >= 3600 && s % 3600 == 0)); then
		echo "$((s / 3600))h"
	elif ((s >= 3600)); then
		echo "$((s / 3600))h$((s % 3600 / 60))m"
	else
		echo "$((s / 60))m"
	fi
}

timeout_notice() {
	if [[ $1 == off ]]; then
		echo "Auto-lock is off."
	else
		echo "It locks after $(fmt_duration "$1") without a read or write."
	fi
}

# off, or the duration in seconds.
parse_timeout() {
	local v=$1 h=0 m=0
	if [[ $v == off ]]; then
		echo off
		return
	elif [[ $v =~ ^([0-9]{1,3})h(([0-9]{1,4})m)?$ ]]; then
		h=${BASH_REMATCH[1]}
		m=${BASH_REMATCH[3]:-0}
	elif [[ $v =~ ^([0-9]{1,5})m$ ]]; then
		m=${BASH_REMATCH[1]}
	else
		die "--timeout=$v: expected off or a duration such as 45m, 1h or 1h30m"
	fi
	local s=$(((10#$h * 60 + 10#$m) * 60))
	((s >= 120)) || die "--timeout=$v: the minimum is 2m, since the notification comes 1m before the lock"
	echo "$s"
}

need_root() {
	((EUID == 0)) || die "run it as root: sudo vault76 $*"
}

current_timeout() {
	local t=""
	if [[ -r $state/timeout ]]; then
		read -r t <"$state/timeout" || true
	fi
	if [[ $t == off || $t =~ ^[0-9]+$ ]]; then
		echo "$t"
	else
		echo "$VAULT76_DEFAULT_TIMEOUT"
	fi
}

# unlock, lock and wipe hold this until they end. The auto-lock only tries
# it and skips its turn, so neither waits for the other.
take_lock() {
	install -d -m 0755 "$state"
	exec 9>"$state/lock"
	flock -w 120 9 || die "another vault76 unlock, lock or wipe is still running"
}

# Applies to the open session; the auto-lock reads it on every poll.
set_timeout() {
	install -d -m 0755 "$state"
	printf '%s\n' "$1" >"$state/timeout.new"
	mv "$state/timeout.new" "$state/timeout"
	touch "$state/reset"
}

# The processes holding files or a working directory on the volume.
# Named by argv[0]: a process systemd starts keeps the start of the command's
# full path as its comm, and coreutils tools share one executable.
holders() {
	local pid name
	for pid in $(fuser -m "$mnt" 2>/dev/null); do
		name=$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | head -n 1) || true
		[[ -n $name ]] || name=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
		printf '%7s %s\n' "$pid" "${name##*/}"
	done
}

# 0: locked. 2: in use, the holders on stdout. 1: a step failed.
lock_volume() {
	if mountpoint -q "$mnt"; then
		local busy
		busy=$(holders) || true
		if [[ -n $busy ]]; then
			echo "$busy"
			return 2
		fi
		systemctl stop "$mount_unit" || return 1
	fi
	systemctl stop "$crypt_unit" || return 1
	if [[ -e $mapper ]]; then
		echo "vault76: $mapper is still open after $crypt_unit stopped" >&2
		return 1
	fi
	rm -f "$state/timeout" "$state/reset"
}

unlock() {
	local timeout=$1
	[[ -e /dev/disk/by-uuid/$VAULT76_UUID ]] || die "the vault76 drive (LUKS UUID $VAULT76_UUID) is not attached"
	take_lock
	if mountpoint -q "$mnt"; then
		echo "vault76 is already unlocked at $mnt"
		[[ -n $timeout ]] || touch "$state/reset"
	else
		systemctl start "$mount_unit" || die "unlock failed; see: journalctl -b -u $crypt_unit -u $mount_unit"
		rm -f "$state/timeout"
	fi
	[[ -z $timeout ]] || set_timeout "$timeout"
	systemctl start "$autolock_unit"
	status
}

lock() {
	local out rc=0
	out=$(lock_volume) || rc=$?
	case $rc in
	0)
		systemctl stop "$autolock_unit"
		echo "vault76 is locked"
		;;
	2)
		printf 'vault76 stays unlocked: these processes use %s:\n%s\n' "$mnt" "$out" >&2
		exit 1
		;;
	*) die "lock failed; see: systemctl status $mount_unit $crypt_unit" ;;
	esac
}

status() {
	if mountpoint -q "$mnt"; then
		local timeout last=""
		timeout=$(current_timeout)
		echo "vault76 is unlocked at $mnt"
		if [[ $timeout == off ]]; then
			echo "auto-lock: off until the next lock"
		else
			echo "auto-lock: after $(fmt_duration "$timeout") without a read or write"
		fi
		if [[ -e $state/reset ]]; then
			echo "idle: 0m"
		else
			if [[ -r $state/last-io ]]; then
				read -r last <"$state/last-io" || true
			fi
			if [[ $last =~ ^[0-9]+$ ]]; then
				echo "idle: $(fmt_duration $(((EPOCHSECONDS - last) / 60 * 60)))"
			fi
		fi
		systemctl is-active --quiet "$autolock_unit" || echo "warning: $autolock_unit is not running, so nothing locks vault76 on idle"
	elif [[ -e $mapper ]]; then
		echo "vault76 is unlocked but not mounted; lock it with: sudo vault76 lock"
	else
		echo "vault76 is locked"
	fi
}

# The key slots in a LUKS2 header.
keyslot_count() {
	cryptsetup luksDump "$1" | awk '/^Keyslots:/ { k = 1; next } /^[A-Z][a-z]+:/ { k = 0 } k && /^ +[0-9]+: / { n++ } END { print n + 0 }'
}

# A header backup restores erased key slots, so the encrypted data goes too.
# Zero-fill (BLKZEROOUT) reads back as zeros on any drive; a plain discard
# guarantees that only where the drive promises it.
wipe() {
	local force=$1 dev answer slots
	dev=$(readlink -f "/dev/disk/by-uuid/$VAULT76_UUID") && [[ -b $dev ]] ||
		die "the vault76 drive (LUKS UUID $VAULT76_UUID) is not attached"
	cryptsetup isLuks "$dev" || die "$dev holds no LUKS header"
	slots=$(keyslot_count "$dev")
	if ((force == 0)); then
		[[ -t 0 ]] || die "wipe asks for confirmation on a terminal; pass --force to skip it"
		cat >&2 <<EOF
This erases vault76 on $dev ($(lsblk -dno SIZE "$dev" | tr -d ' ')): its $slots key slots, then every
block of the partition. No YubiKey, passphrase or header backup opens it again.
EOF
		read -r -p "Type vault76 to erase it: " answer || answer=""
		[[ $answer == vault76 ]] || die "not confirmed; nothing was erased"
	fi
	take_lock
	lock
	echo "erasing $slots key slots of $dev"
	cryptsetup luksErase -q "$dev" || die "luksErase failed; the key slots may be intact"
	slots=$(keyslot_count "$dev")
	((slots == 0)) || die "luksErase finished, but $slots key slots remain"
	echo "zero-filling $dev"
	blkdiscard -f -z "$dev" ||
		die "the key slots are erased, but zero-filling $dev failed: a header backup still opens its data"
	echo "vault76 is erased: no key slot is left and $dev reads as zeros."
	echo "Destroy every header backup too, and remove vault76.nix from the configuration."
}

# Read and write completions of the dm device; page-cache hits never reach it.
io_counters() {
	local dm r w
	dm=$(basename "$(readlink -f "$mapper")")
	read -r r _ _ _ w _ <"/sys/block/$dm/stat" || return 1
	echo "$r $w"
}

# Fills notify_argv with the command that reaches the owner's desktop.
notify_cmd() {
	local uid gid bus
	if ! uid=$(id -u "$VAULT76_OWNER" 2>/dev/null) || ! gid=$(id -g "$VAULT76_OWNER" 2>/dev/null); then
		echo "no user $VAULT76_OWNER; notification not shown" >&2
		return 1
	fi
	bus=/run/user/$uid/bus
	[[ -S $bus ]] || {
		echo "no session bus for $VAULT76_OWNER; notification not shown" >&2
		return 1
	}
	notify_argv=(env "DBUS_SESSION_BUS_ADDRESS=unix:path=$bus" setpriv "--reuid=$uid" "--regid=$gid" --init-groups --
		notify-send -a vault76 -h string:x-dunst-stack-tag:vault76 -h string:x-canonical-private-synchronous:vault76)
}

# urgency, summary, body; replaces the previous vault76 notification.
notify() {
	echo "$2: $3" >&2
	local notify_argv
	notify_cmd || return 0
	"${notify_argv[@]}" -u "$1" -- "$2" "$3" || echo "notify-send failed" >&2
}

autolock() {
	install -d -m 0755 "$state"
	local last_io=$EPOCHSECONDS prev="" cur timeout idle warned_at=0 warn_pid=0 busy_noted=0 failed_noted=0 out rc action
	stop_warning() {
		if ((warn_pid > 0)); then
			kill "$warn_pid" 2>/dev/null || true
			wait "$warn_pid" 2>/dev/null || true
		fi
		warn_pid=0
		warned_at=0
		rm -f "$state/action"
	}
	# A read or write, the Keep unlocked action, or vault76 unlock restarts the clock.
	restart_clock() {
		last_io=$EPOCHSECONDS
		busy_noted=0
		failed_noted=0
		if ((warned_at > 0)); then
			stop_warning
			notify normal "vault76 stays unlocked" "$1"
		fi
	}
	trap 'stop_warning; exit 0' TERM INT
	while mountpoint -q "$mnt"; do
		timeout=$(current_timeout)
		if cur=$(io_counters) && [[ $cur != "$prev" ]]; then
			[[ -z $prev ]] || restart_clock "The drive was read or written."
			prev=$cur
		fi
		if [[ -e $state/reset ]]; then
			rm -f "$state/reset"
			restart_clock "$(timeout_notice "$timeout")"
		fi
		# Empty while the warning waits for an answer.
		action=""
		if [[ -r $state/action ]]; then
			read -r action <"$state/action" || true
		fi
		if [[ $action == default ]]; then
			restart_clock "$(timeout_notice "$timeout")"
		fi
		printf '%s\n' "$last_io" >"$state/last-io.new"
		mv "$state/last-io.new" "$state/last-io"
		if [[ $timeout == off ]]; then
			((warned_at == 0)) || stop_warning
		else
			idle=$((EPOCHSECONDS - last_io))
			if ((warned_at == 0 && idle >= timeout - warn_s)); then
				warned_at=$EPOCHSECONDS
				echo "idle for $(fmt_duration "$idle"): warning before the lock" >&2
				local notify_argv
				if notify_cmd; then
					rm -f "$state/action"
					# exec keeps notify-send's pid in warn_pid; it waits for the action.
					(exec "${notify_argv[@]}" -u critical -A "default=Keep unlocked" -- "vault76 locks in 1 minute" \
						"No read or write for $(fmt_duration "$idle"). Middle-click this notification, or use the drive, to keep it unlocked." \
						>"$state/action") &
					warn_pid=$!
				fi
			fi
			# The lock waits a full minute after the warning, also after a suspend.
			if ((warned_at > 0 && idle >= timeout && EPOCHSECONDS - warned_at >= warn_s)); then
				rc=0
				out=$(
					exec 9>"$state/lock"
					flock -n 9 || exit 3
					lock_volume
				) || rc=$?
				case $rc in
				0)
					stop_warning
					notify normal "vault76 locked" "No read or write for $(fmt_duration "$idle")."
					exit 0
					;;
				2)
					if ((busy_noted == 0)); then
						busy_noted=1
						notify critical "vault76 stays unlocked" "In use by: $(awk '{print $2}' <<<"$out" | sort -u | paste -sd' ' | sed 's/&/\&amp;/g; s/</\&lt;/g'). It locks once they release it."
					fi
					;;
				# A vault76 command is running; it decides.
				3) ;;
				*)
					if ((failed_noted == 0)); then
						failed_noted=1
						notify critical "vault76 failed to lock" "It retries every $poll_s s. See: systemctl status $mount_unit $crypt_unit"
					fi
					;;
				esac
			fi
		fi
		sleep "$poll_s" &
		wait $! || true
	done
	stop_warning
	# Unmounted but still open, as after a failed mount or a stop of the mount
	# alone. Exit 3: a vault76 command holds the lock, or nothing is left open.
	rc=0
	(
		exec 9>"$state/lock"
		flock -n 9 || exit 3
		mountpoint -q "$mnt" && exit 3
		rm -f "$state/timeout" "$state/reset" "$state/last-io"
		[[ -e $mapper ]] || exit 3
		systemctl stop "$crypt_unit" || true
		[[ ! -e $mapper ]]
	) || rc=$?
	case $rc in
	0) notify normal "vault76 locked" "It was unmounted." ;;
	3) ;;
	*) notify critical "vault76 failed to lock" "It is unmounted, but $mapper is still open. See: systemctl status $crypt_unit" ;;
	esac
}

opts=$(getopt -o t:fh -l timeout:,force,help -n vault76 -- "$@") || {
	usage >&2
	exit 2
}
eval set -- "$opts"
timeout="" force=0
while true; do
	case $1 in
	-t | --timeout)
		timeout=$(parse_timeout "$2") || exit 1
		shift
		;;
	-f | --force) force=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	esac
	shift
done
if (($# == 0)); then
	usage >&2
	exit 2
fi
cmd=$1
shift
(($# == 0)) || die "unexpected argument: $1"
[[ -z $timeout || $cmd == unlock ]] || die "--timeout goes with unlock"
((force == 0)) || [[ $cmd == wipe ]] || die "--force goes with wipe"
case $cmd in
unlock)
	need_root unlock
	unlock "$timeout"
	;;
lock)
	need_root lock
	take_lock
	lock
	;;
wipe)
	need_root wipe
	wipe "$force"
	;;
status) status ;;
help) usage ;;
# The loop vault76-autolock.service runs.
autolock-daemon)
	need_root autolock-daemon
	autolock
	;;
*)
	echo "vault76: unknown command: $cmd" >&2
	usage >&2
	exit 2
	;;
esac
