#!/usr/bin/env bash
# Archives and drops git stashes older than an age threshold. Recoverability
# is the design constraint: a stash is only dropped after its commit is
# archived under refs/stash-archive/<YYYY-MM-DD>/<short-sha>, and archive
# refs are only deleted by an explicit --sweep-archive past the retention
# window. `git stash clear` is never used; every drop is per-stash.
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"

usage() {
  # Help requested explicitly (-h/--help) prints to stdout; callers on the
  # error path redirect this to stderr with `usage >&2`.
  cat <<EOF
usage: ${prog_name} [options]

Prunes stashes older than --age (default 14d). Dry-run by default: prints
the plan and changes nothing; --apply performs it. Every pruned stash is
archived under refs/stash-archive/<YYYY-MM-DD>/<short-sha> (archive date,
12-hex short sha) before the drop; a failed archive write aborts that
stash's drop and the run exits non-zero.

Recover a pruned stash within the retention window:
  git stash apply refs/stash-archive/<YYYY-MM-DD>/<short-sha>

options:
  --apply                   Archive and drop selected stashes.
  --age <dur>               Age threshold. Formats: 14d, 2w, bare integer
                            (days). Default: 14d.
  --archive-retention <dur> Grace period for archive refs. Default: 90d.
  --sweep-archive           Also delete archive refs whose archive date is
                            past the retention window (dry-run without
                            --apply).
  --all-worktrees           Also process repositories under
                            \$HOME/trees/nixos. Roots sharing a common git
                            dir are processed once: linked worktrees share
                            one stash stack.
  -h, --help                Print this help.

Runs are serialized by a per-user lock; a second concurrent invocation exits
1 rather than resolving stash positions against a stack another run is
mutating.

exit codes:
  0   success (or clean dry-run)
  1   at least one archive write or drop failed, the stash list could not be
      read, or another instance holds the run lock
  64  usage error
EOF
}

parse_duration_days() {
  # Digits are normalized through 10# here because the result is re-evaluated
  # by later arithmetic, where a leading zero means octal: `010` would become a
  # 10-day threshold read back as 8, and `08`/`09` abort with "value too great
  # for base".
  local spec=$1
  if [[ $spec =~ ^([0-9]+)d?$ ]]; then
    printf '%s' "$((10#${BASH_REMATCH[1]}))"
  elif [[ $spec =~ ^([0-9]+)w$ ]]; then
    printf '%s' "$((10#${BASH_REMATCH[1]} * 7))"
  else
    echo "${prog_name}: invalid duration '${spec}' (expected e.g. 14d, 2w, 30)" >&2
    return 64
  fi
}

apply=false
sweep=false
all_worktrees=false
age_days=14
retention_days=90

while [[ $# -gt 0 ]]; do
  case "$1" in
  --apply)
    apply=true
    shift
    ;;
  --sweep-archive)
    sweep=true
    shift
    ;;
  --all-worktrees)
    all_worktrees=true
    shift
    ;;
  --age)
    [[ $# -ge 2 ]] || {
      echo "${prog_name}: --age requires a value" >&2
      exit 64
    }
    age_days=$(parse_duration_days "$2") || exit 64
    shift 2
    ;;
  --age=*)
    age_days=$(parse_duration_days "${1#*=}") || exit 64
    shift
    ;;
  --archive-retention)
    [[ $# -ge 2 ]] || {
      echo "${prog_name}: --archive-retention requires a value" >&2
      exit 64
    }
    retention_days=$(parse_duration_days "$2") || exit 64
    shift 2
    ;;
  --archive-retention=*)
    retention_days=$(parse_duration_days "${1#*=}") || exit 64
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "${prog_name}: unknown argument: $1" >&2
    usage >&2
    exit 64
    ;;
  esac
done

now=$(date +%s)
age_cutoff=$((now - age_days * 86400))
retention_cutoff=$((now - retention_days * 86400))
archive_date=$(date -u +%F)
failures=0
selected=0

# Collect candidate roots, then deduplicate by resolved common git dir so a
# stash stack shared by linked worktrees is only processed once.
declare -a roots=()
if toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
  roots+=("$toplevel")
fi
if [[ $all_worktrees == true ]]; then
  for dir in "$HOME"/trees/nixos/*/; do
    [[ -d $dir ]] || continue
    if wt_top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
      roots+=("$wt_top")
    fi
  done
fi
if [[ ${#roots[@]} -eq 0 ]]; then
  echo "${prog_name}: not inside a git repository and no repositories found under \$HOME/trees/nixos" >&2
  exit 64
fi

declare -A seen_common=()
declare -a repos=()
for root in "${roots[@]}"; do
  common=$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  [[ -n ${seen_common[$common]:-} ]] && continue
  seen_common[$common]=1
  repos+=("$root")
done

# Prints the current stack position of a stash commit. Exit 1 when the commit
# is no longer stashed, 2 when the stack cannot be read at all.
locate_stash_index() {
  local repo=$1 want=$2 live listed pos=0
  live=$(git -C "$repo" stash list --format='%H') || return 2
  while IFS= read -r listed; do
    [[ -n $listed ]] || continue
    if [[ $listed == "$want" ]]; then
      printf '%s' "$pos"
      return 0
    fi
    pos=$((pos + 1))
  done <<<"$live"
  return 1
}

prune_repo() {
  local repo=$1
  local -a positions=() shas=() ctimes=() subjects=()
  local listing gd ct sha subject idx pos=0

  echo "repo: ${repo}"

  # The listing is captured with its exit status rather than piped in from a
  # process substitution, whose failure is invisible: the loop would read zero
  # lines and an unreadable repository would be reported as a clean result.
  if ! listing=$(git -C "$repo" stash list --format='%gd|%ct|%H|%s'); then
    echo "  ERROR: cannot read the stash list of ${repo}" >&2
    failures=$((failures + 1))
    return 0
  fi

  while IFS='|' read -r gd ct sha subject; do
    [[ -n $gd ]] || continue
    # Entries that do not have the expected shape are rejected, not treated as
    # old: an empty ct evaluates as 0 and would select the entry unconditionally.
    if [[ ! $ct =~ ^[0-9]+$ || ! $sha =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
      echo "  ERROR: unparsable stash list entry: ${gd}" >&2
      failures=$((failures + 1))
      # A rejected entry still occupies a stack slot, so the counter has to
      # advance or every position below it is reported one too low.
      pos=$((pos + 1))
      continue
    fi
    if ((ct <= age_cutoff)); then
      positions+=("$pos")
      shas+=("$sha")
      ctimes+=("$ct")
      subjects+=("$subject")
    fi
    pos=$((pos + 1))
  done <<<"$listing"

  local count=${#shas[@]}
  if ((count == 0)); then
    echo "  no stashes older than ${age_days}d"
    return 0
  fi

  # Iterate from the highest stash index down: dropping stash@{N} shifts
  # every index above N, but never the lower ones still pending.
  local i age_d ref current located rc
  for ((i = count - 1; i >= 0; i--)); do
    sha=${shas[i]}
    age_d=$(((now - ctimes[i]) / 86400))
    ref="refs/stash-archive/${archive_date}/${sha:0:12}"
    selected=$((selected + 1))

    if [[ $apply != true ]]; then
      echo "  would archive stash@{${positions[i]}} (${age_d}d old) -> ${ref}"
      echo "    ${subjects[i]}"
      continue
    fi

    # The position recorded at listing time is a snapshot: one `git stash push`
    # from another shell shifts every index, and asserting the stale one would
    # fail every remaining candidate even though each is still present and
    # still eligible. The live position is resolved from the recorded sha, so
    # the identity of what gets dropped never depends on the snapshot.
    rc=0
    located=$(locate_stash_index "$repo" "$sha") || rc=$?
    if ((rc == 2)); then
      echo "  ERROR: cannot re-read the stash list of ${repo}; not dropping ${sha}" >&2
      failures=$((failures + 1))
      continue
    elif ((rc != 0)); then
      echo "  ERROR: ${sha} is no longer in the stash stack of ${repo}; skipping its drop" >&2
      failures=$((failures + 1))
      continue
    fi
    idx=$located

    echo "  archiving stash@{${idx}} (${age_d}d old) -> ${ref}"
    echo "    ${subjects[i]}"
    if ! git -C "$repo" update-ref "$ref" "$sha"; then
      echo "  ERROR: archive write failed for stash@{${idx}}; NOT dropping it" >&2
      failures=$((failures + 1))
      continue
    fi
    # Last check before the destructive step: the archive above is keyed by sha
    # and costs nothing if this fails, but the drop is keyed by index.
    current=$(git -C "$repo" rev-parse --verify --quiet "stash@{${idx}}") || current=""
    if [[ $current != "$sha" ]]; then
      echo "  ERROR: stash@{${idx}} no longer resolves to ${sha}; skipping its drop (archive ref ${ref} kept)" >&2
      failures=$((failures + 1))
      continue
    fi
    if ! git -C "$repo" stash drop "stash@{${idx}}" >/dev/null; then
      echo "  ERROR: drop failed for stash@{${idx}} (archive ref ${ref} kept)" >&2
      failures=$((failures + 1))
      continue
    fi
    echo "  dropped stash@{${idx}} (recover: git stash apply ${ref})"
  done
}

sweep_repo() {
  local repo=$1
  local archive_refs ref date_part epoch

  # Captured with its status for the same reason as the stash listing: a
  # for-each-ref failure inside a process substitution would look like a
  # repository that simply has no archive refs left to expire.
  if ! archive_refs=$(git -C "$repo" for-each-ref --format='%(refname)' 'refs/stash-archive/'); then
    echo "  ERROR: cannot read archive refs of ${repo}" >&2
    failures=$((failures + 1))
    return 0
  fi

  while read -r ref; do
    [[ -n $ref ]] || continue
    date_part=${ref#refs/stash-archive/}
    date_part=${date_part%%/*}
    if ! epoch=$(date -u -d "$date_part" +%s 2>/dev/null); then
      echo "  skipping archive ref with unparsable date: ${ref}" >&2
      continue
    fi
    ((epoch <= retention_cutoff)) || continue
    if [[ $apply == true ]]; then
      if git -C "$repo" update-ref -d "$ref"; then
        echo "  deleted archive ref ${ref} (past ${retention_days}d retention)"
      else
        echo "  ERROR: failed to delete archive ref ${ref}" >&2
        failures=$((failures + 1))
      fi
    else
      echo "  would delete archive ref ${ref} (past ${retention_days}d retention)"
    fi
  done <<<"$archive_refs"
}

# Serialize runs the way the sibling destructive helper does
# (scripts/prune-stale-worktrees.sh): two runs over one stash stack would each
# resolve positions against a stack the other is mutating. Dry runs take the
# lock too, so a report is never printed against a stack being pruned.
lock_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
lock_file="${lock_dir}/prune-old-stashes.$(id -u).lock"
exec 200>"${lock_file}"
flock -n 200 || {
  echo "${prog_name}: another instance is already running (lock: ${lock_file})" >&2
  exit 1
}

for repo in "${repos[@]}"; do
  prune_repo "$repo"
  if [[ $sweep == true ]]; then
    sweep_repo "$repo"
  fi
done

if [[ $apply != true ]]; then
  echo
  if ((selected > 0)); then
    echo "dry-run: ${selected} stash(es) selected; no changes made. Re-run with --apply."
  else
    echo "dry-run: nothing selected; no changes made."
  fi
fi

if ((failures > 0)); then
  echo "${prog_name}: ${failures} failure(s)" >&2
  exit 1
fi
