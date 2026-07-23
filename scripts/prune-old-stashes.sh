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

exit codes:
  0   success (or clean dry-run)
  1   at least one archive write or drop failed
  64  usage error
EOF
}

parse_duration_days() {
  local spec=$1
  if [[ $spec =~ ^([0-9]+)d?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ $spec =~ ^([0-9]+)w$ ]]; then
    printf '%s' "$((BASH_REMATCH[1] * 7))"
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

prune_repo() {
  local repo=$1
  local -a idxs=() shas=() ctimes=() subjects=()
  local gd ct sha subject idx

  while IFS='|' read -r gd ct sha subject; do
    [[ -n $gd ]] || continue
    idx=${gd#stash@\{}
    idx=${idx%\}}
    if ((ct <= age_cutoff)); then
      idxs+=("$idx")
      shas+=("$sha")
      ctimes+=("$ct")
      subjects+=("$subject")
    fi
  done < <(git -C "$repo" stash list --format='%gd|%ct|%H|%s')

  echo "repo: ${repo}"
  local count=${#idxs[@]}
  if ((count == 0)); then
    echo "  no stashes older than ${age_days}d"
    return 0
  fi

  # Iterate from the highest stash index down: dropping stash@{N} shifts
  # every index above N, but never the lower ones still pending.
  local i age_d ref current
  for ((i = count - 1; i >= 0; i--)); do
    idx=${idxs[i]}
    sha=${shas[i]}
    age_d=$(((now - ctimes[i]) / 86400))
    ref="refs/stash-archive/${archive_date}/${sha:0:12}"
    selected=$((selected + 1))

    if [[ $apply != true ]]; then
      echo "  would archive stash@{${idx}} (${age_d}d old) -> ${ref}"
      echo "    ${subjects[i]}"
      continue
    fi

    echo "  archiving stash@{${idx}} (${age_d}d old) -> ${ref}"
    echo "    ${subjects[i]}"
    current=$(git -C "$repo" rev-parse --verify --quiet "stash@{${idx}}") || current=""
    if [[ $current != "$sha" ]]; then
      echo "  ERROR: stash@{${idx}} no longer resolves to ${sha}; skipping its drop" >&2
      failures=$((failures + 1))
      continue
    fi
    if ! git -C "$repo" update-ref "$ref" "$sha"; then
      echo "  ERROR: archive write failed for stash@{${idx}}; NOT dropping it" >&2
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
  local ref date_part epoch
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
  done < <(git -C "$repo" for-each-ref --format='%(refname)' 'refs/stash-archive/')
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
