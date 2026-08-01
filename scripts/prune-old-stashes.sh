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
  --age <dur>               Age threshold, also --age=<dur>. Formats: 14d,
                            2w, bare integer (days). Default: 14d. 0
                            selects every stash; unlike
                            --archive-retention 0 it disables nothing.
  --archive-retention <dur> Grace period for archive refs, also
                            --archive-retention=<dur>. Default: 90d. A
                            value of 0 disables expiry, as it does for
                            --backup-retention-days in
                            prune-stale-worktrees.
  --sweep-archive           Also delete archive refs whose archive date is
                            past the retention window (dry-run without
                            --apply). Refs written under today's date are
                            never swept, so a single invocation cannot
                            delete the archive of a stash it just dropped.
  --all-worktrees           Also process repositories under each --root.
                            Roots sharing a common git dir are processed
                            once: linked worktrees share one stash stack.
  --root <dir>              Repeatable, also --root=<dir>. Directory
                            scanned by --all-worktrees; a usage error
                            without it. Default: \$HOME/trees/nixos.
                            Exactly one level below each root is scanned,
                            so a root must directly contain the checkouts;
                            unlike prune-stale-worktrees, container
                            directories are not descended into. A named
                            root that is missing, or that contains no
                            checkouts, is reported and counted as a
                            failure.
  -h, --help                Print this help.

Runs are serialized by a per-user lock; a second concurrent invocation exits
1 rather than resolving stash positions against a stack another run is
mutating.

exit codes:
  0   success (or clean dry-run)
  1   the run did not complete everything it selected. Causes: an archive
      write, drop, or archive-ref deletion failed; a selected stash moved or
      vanished before its drop; a stash-list entry was unparsable; the stash
      list or the archive refs could not be read; a named --root is missing,
      contains no checkouts, or holds a broken checkout or a directory that
      is not the root of the repository it resolves to; another instance
      holds the run lock
  64  usage error
EOF
}

parse_duration_days() {
  # Digits are normalized through 10# here because the result is re-evaluated
  # by later arithmetic, where a leading zero means octal: `010` would become a
  # 10-day threshold read back as 8, and `08`/`09` abort with "value too great
  # for base".
  #
  # The digit run is bounded because that arithmetic is 64-bit and wraps
  # silently: `--age 999999999999999` puts age_cutoff in the future, so every
  # stash satisfies `ct <= age_cutoff` and a threshold asking to keep
  # everything selects a stash pushed seconds ago. Out of range now takes the
  # documented exit-64 path.
  local spec=$1
  if [[ $spec =~ ^([0-9]{1,6})d?$ ]]; then
    printf '%s' "$((10#${BASH_REMATCH[1]}))"
  elif [[ $spec =~ ^([0-9]{1,6})w$ ]]; then
    printf '%s' "$((10#${BASH_REMATCH[1]} * 7))"
  else
    echo "${prog_name}: invalid duration '${spec}' (expected e.g. 14d, 2w, 30; at most 6 digits)" >&2
    return 64
  fi
}

apply=false
sweep=false
all_worktrees=false
declare -a scan_roots=()
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
  --root)
    [[ $# -ge 2 ]] || {
      echo "${prog_name}: --root requires a value" >&2
      exit 64
    }
    scan_roots+=("$2")
    shift 2
    ;;
  --root=*)
    scan_roots+=("${1#*=}")
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
# The extra day is the one the ref name cannot express: archive refs carry a
# date, so `epoch` is midnight of that date while the cutoff is an instant.
# Without it, `--archive-retention N` grants only N-1 days of grace; a ref
# written yesterday at 23:00 would be deleted by a run at 00:30 today with
# `--archive-retention 1`, 90 minutes after it was written.
retention_cutoff=$((now - (retention_days + 1) * 86400))
archive_date=$(date -u +%F)
failures=0
selected=0
would_sweep=0
dropped=0
swept=0

# Collect candidate roots, then deduplicate by resolved common git dir so a
# stash stack shared by linked worktrees is only processed once.
declare -a roots=()
if toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
  roots+=("$toplevel")
fi
# A --root that is never scanned is a typo, not a preference: silently
# ignoring it prunes only the current repository while the operator believes a
# whole tree was covered.
if [[ ${#scan_roots[@]} -gt 0 && $all_worktrees != true ]]; then
  echo "${prog_name}: --root has no effect without --all-worktrees" >&2
  exit 64
fi
if [[ $all_worktrees == true ]]; then
  roots_explicit=true
  if [[ ${#scan_roots[@]} -eq 0 ]]; then
    roots_explicit=false
    scan_roots=("$HOME/trees/nixos")
  fi
  for scan_root in "${scan_roots[@]}"; do
    # An empty value makes the glob below expand to `/*/`, enumerating every
    # top-level directory of the filesystem root; a mistyped one matches
    # nothing and reports a clean run over a tree that was never scanned.
    if [[ -z $scan_root || ! -d $scan_root ]]; then
      echo "${prog_name}: root does not exist, skipping: ${scan_root}" >&2
      # A root the operator named and misspelled belongs in the exit status.
      # The default one simply may not exist on a host without worktrees.
      if [[ $roots_explicit == true ]]; then
        failures=$((failures + 1))
      fi
      continue
    fi
    scanned=0
    anomalies=0
    for dir in "$scan_root"/*/; do
      [[ -d $dir ]] || continue
      # rev-parse walks up, so a directory that is not itself a checkout
      # resolves to whatever repository encloses the root: one plain directory
      # under the root is enough to pull a dotfiles repo at $HOME into the scan
      # set and prune its stashes.
      [[ -e ${dir%/}/.git ]] || continue
      if wt_top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
        # Presence of .git is not the property being relied on; "this directory
        # is the repository root" is. Git treats .git as a repository only when
        # it validates, so an empty or partially deleted .git directory does not
        # stop discovery and rev-parse walks up to the enclosing repository. A
        # non-empty prefix says the repository found is not rooted here.
        if [[ -n $(git -C "$dir" rev-parse --show-prefix 2>/dev/null) ]]; then
          echo "${prog_name}: not a checkout root, skipping: ${dir%/}" >&2
          failures=$((failures + 1))
          anomalies=$((anomalies + 1))
          continue
        fi
        roots+=("$wt_top")
        scanned=$((scanned + 1))
      else
        # A .git that does not resolve is a broken checkout, not an absence:
        # left silent it is indistinguishable from one that was processed,
        # while its stashes stay outside the tool's reach. Counted whichever
        # root it came from, unlike a missing or empty root: the default root
        # is exempt because a host may legitimately have no worktrees, and
        # corruption inside an existing tree is not that case.
        echo "${prog_name}: broken checkout, skipping: ${dir%/}" >&2
        failures=$((failures + 1))
        anomalies=$((anomalies + 1))
      fi
    done
    # Exactly one level is scanned, so a root aimed one level too high exists,
    # matches directories, and still registers nothing. Left silent that is the
    # same clean report over an unscanned tree a missing root already reports.
    # Only when nothing was found at all: a root whose entries were reported as
    # broken or misrooted does contain checkouts, and calling that an absence
    # would both misdescribe it and count one problem twice.
    if ((scanned == 0 && anomalies == 0)); then
      echo "${prog_name}: no checkouts directly under root: ${scan_root}" >&2
      if [[ $roots_explicit == true ]]; then
        failures=$((failures + 1))
      fi
    fi
  done
fi
if [[ ${#roots[@]} -eq 0 ]]; then
  echo "${prog_name}: not inside a git repository and no repositories found under the scanned roots" >&2
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
  # An empty stack means the commit is not there. Handled here rather than by
  # skipping blank lines in the loop: a blank line inside a non-empty listing
  # occupies a stack slot, and stepping over it would resolve every commit
  # below it one index too low.
  [[ -n $live ]] || return 1
  while IFS= read -r listed; do
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
  local listing gd ct sha subject idx pos=0 stack_unreadable=false

  echo "repo: ${repo}"

  # The listing is captured with its exit status rather than piped in from a
  # process substitution, whose failure is invisible: the loop would read zero
  # lines and an unreadable repository would be reported as a clean result.
  if ! listing=$(git -C "$repo" stash list --format='%gd|%ct|%H|%s'); then
    echo "  ERROR: cannot read the stash list of ${repo}" >&2
    failures=$((failures + 1))
    return 1
  fi

  # An empty listing is the "no stashes" case and is handled here rather than
  # by skipping blank lines inside the loop: a blank line in a non-empty
  # listing occupies a stack slot like any other and must be rejected loudly,
  # not stepped over without advancing the position.
  if [[ -n $listing ]]; then
    while IFS='|' read -r gd ct sha subject; do
      # Entries that do not have the expected shape are rejected, not treated
      # as old: an empty ct evaluates as 0 and would select the entry
      # unconditionally.
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
  fi

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
      stack_unreadable=true
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
    dropped=$((dropped + 1))
  done
  # Same failure state as the initial listing: a repository whose stash list
  # this run could not read must not have its archive refs expired, since they
  # are the only copies of stashes already dropped there.
  if [[ $stack_unreadable == true ]]; then
    return 1
  fi
  return 0
}

sweep_repo() {
  local repo=$1
  local archive_refs ref date_part epoch

  # 0 disables expiry, matching --backup-retention-days in
  # scripts/prune-stale-worktrees.sh. The same operator drives both helpers, so
  # the value must not mean "keep everything" in one and "delete everything" in
  # the other. Said out loud rather than returned silently: the same command
  # deleted every archive ref before that alignment.
  if ((retention_days == 0)); then
    echo "  archive retention disabled (--archive-retention 0); no archive refs expired"
    return 0
  fi

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
    # Refs bearing this run's archive date are never expired. prune_repo runs
    # first, so with --archive-retention 0 the sweep would otherwise delete the
    # archive of a stash dropped moments earlier and leave it irrecoverable,
    # which is the one guarantee this tool exists to provide. Ref names carry
    # only a date, so "written by this run" cannot be narrowed below a day.
    if [[ $date_part == "$archive_date" ]]; then
      continue
    fi
    # `date -u -d` accepts far more than a calendar date: `@0` resolves to the
    # epoch and `yesterday` to a real timestamp, either of which would drive an
    # update-ref -d. The shape is checked first, as everywhere else in this
    # script that an input reaches a decision.
    if [[ ! $date_part =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "  skipping archive ref with a non-date component: ${ref}" >&2
      continue
    fi
    if ! epoch=$(date -u -d "$date_part" +%s 2>/dev/null); then
      echo "  skipping archive ref with unparsable date: ${ref}" >&2
      continue
    fi
    ((epoch <= retention_cutoff)) || continue
    if [[ $apply == true ]]; then
      if git -C "$repo" update-ref -d "$ref"; then
        echo "  deleted archive ref ${ref} (past ${retention_days}d retention)"
        swept=$((swept + 1))
      else
        echo "  ERROR: failed to delete archive ref ${ref}" >&2
        failures=$((failures + 1))
      fi
    else
      echo "  would delete archive ref ${ref} (past ${retention_days}d retention)"
      would_sweep=$((would_sweep + 1))
    fi
  done <<<"$archive_refs"
  # Explicit, like prune_repo: this is the last command of the for body under
  # errexit, so leaking the loop's trailing status would abort the run before
  # the remaining repositories and before the failure summary.
  return 0
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
  # A repository whose stash list could not be read is not swept. Its archive
  # refs are the only copies of stashes already dropped there, and expiring
  # them is the wrong move precisely when the repository is in a failure state.
  if prune_repo "$repo" && [[ $sweep == true ]]; then
    sweep_repo "$repo"
  fi
done

# Both modes close with a total. `selected` counts stashes attempted, and any
# of the drop-loop gates can reject one, so the destructive mode is the one
# where an operator most needs the count of what actually happened.
echo
if [[ $apply != true ]]; then
  if ((selected > 0 || would_sweep > 0)); then
    echo "dry-run: ${selected} stash(es) and ${would_sweep} archive ref(s) selected; no changes made. Re-run with --apply."
  else
    echo "dry-run: nothing selected; no changes made."
  fi
else
  echo "applied: ${dropped} stash(es) archived and dropped, ${swept} archive ref(s) deleted."
fi

if ((failures > 0)); then
  echo "${prog_name}: ${failures} failure(s)" >&2
  exit 1
fi
