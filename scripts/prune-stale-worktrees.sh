#!/usr/bin/env bash
# Prunes local branches whose upstream is gone on the remote, together with
# the worktrees backing them. Dry-run by default; --apply performs safe
# deletions; --force additionally handles unpushed commits and dirty
# worktrees after preserving their state (backup ref, stash).
#
# Deleted branch tips are always preserved under refs/prune-backup/<branch>/<epoch>
# because this repository squash-merges PRs, so `git branch -d` can never
# confirm merged-ness and recoverability must come from backups instead.
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<EOF
usage: ${prog_name} [options]

Detects local branches whose upstream tracking branch is gone after
'git fetch --all --prune', then removes the matching worktree under the
scanned roots and deletes the local branch. Dry-run unless --apply.

options:
  --apply                     perform safe deletions (default: dry-run)
  --force                     also prune candidates with unpushed commits or a
                              dirty worktree; unpushed tips are kept as backup
                              refs and dirty state is stashed first (implies
                              --apply)
  --root DIR                  worktree root to scan (repeatable,
                              default: \$HOME/trees)
  --repo DIR                  repository to scan even when it has no worktree
                              under the roots (repeatable)
  --include GLOB              only consider branches matching GLOB (repeatable)
  --exclude GLOB              skip branches matching GLOB (repeatable)
  --backup-retention-days N   expire refs/prune-backup/* after N days
                              (default: 90, 0 disables expiry)
  --json                      emit a machine-readable summary on stdout
  -h, --help                  show this help

exit codes:
  0  success (dry-run always exits 0 unless a hard error occurs)
  1  hard error (usage, lock contention, missing helper)
  2  apply mode: a candidate was blocked by a safety check or a repository
     could not be scanned (failed fetch, missing --repo path)
EOF
}

error_msg() {
  printf '%s: %s\n' "${prog_name}" "$1" >&2
}

die() {
  error_msg "$1"
  exit 1
}

mode=dry-run
declare -a roots=()
declare -a extra_repos=()
declare -a include_globs=()
declare -a exclude_globs=()
backup_retention_days=90
json_output=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --apply)
    if [[ ${mode} == dry-run ]]; then mode=apply; fi
    shift
    ;;
  --force)
    mode=force
    shift
    ;;
  --root)
    [[ $# -ge 2 ]] || die "--root requires a directory argument"
    roots+=("$2")
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || die "--repo requires a directory argument"
    extra_repos+=("$2")
    shift 2
    ;;
  --include)
    [[ $# -ge 2 ]] || die "--include requires a glob argument"
    include_globs+=("$2")
    shift 2
    ;;
  --exclude)
    [[ $# -ge 2 ]] || die "--exclude requires a glob argument"
    exclude_globs+=("$2")
    shift 2
    ;;
  --backup-retention-days)
    [[ $# -ge 2 && $2 =~ ^[0-9]+$ ]] || die "--backup-retention-days requires a non-negative integer"
    backup_retention_days="$2"
    shift 2
    ;;
  --json)
    json_output=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done

if [[ ${#roots[@]} -eq 0 ]]; then
  roots=("${HOME}/trees")
fi

if ${json_output} && ! command -v jq >/dev/null 2>&1; then
  die "--json requires jq on PATH"
fi

find_remove_helper() {
  if [[ -n ${PRUNE_WORKTREE_REMOVE_HELPER:-} ]]; then
    printf '%s\n' "${PRUNE_WORKTREE_REMOVE_HELPER}"
    return 0
  fi
  if [[ -x "${script_dir}/git-worktree-remove-safe.sh" ]]; then
    printf '%s\n' "${script_dir}/git-worktree-remove-safe.sh"
    return 0
  fi
  if command -v git-worktree-remove-safe >/dev/null 2>&1; then
    command -v git-worktree-remove-safe
    return 0
  fi
  return 1
}

remove_helper="$(find_remove_helper)" ||
  die "git-worktree-remove-safe helper not found (set PRUNE_WORKTREE_REMOVE_HELPER)"

lock_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
lock_file="${lock_dir}/prune-stale-worktrees.$(id -u).lock"
exec 200>"${lock_file}"
flock -n 200 || die "another instance is already running (lock: ${lock_file})"

now_epoch="$(date +%s)"

# Global counters and record accumulators.
count_removed=0
count_would_remove=0
count_blocked=0
count_orphans=0
count_still_remote=0
count_no_upstream=0
count_backups_expired=0

declare -a repo_records=()
declare -a branch_records=()
declare -a orphan_records=()

log_line() {
  if ! ${json_output}; then
    printf '%s\n' "$1"
  fi
}

record_repo() {
  local path fetch_state
  path="$1"
  fetch_state="$2"
  repo_records+=("${path}"$'\t'"${fetch_state}")
  log_line "repo=${path} fetch=${fetch_state}"
}

# record_branch <repo> <branch> <worktree> <state> <reason> <pushed> <drift>
record_branch() {
  local repo branch worktree state reason pushed drift line
  repo="$1"
  branch="$2"
  worktree="$3"
  state="$4"
  reason="$5"
  pushed="$6"
  drift="$7"
  branch_records+=("${repo}"$'\t'"${branch}"$'\t'"${worktree}"$'\t'"${state}"$'\t'"${reason}"$'\t'"${pushed}"$'\t'"${drift}")
  line="branch=${branch} repo=${repo} worktree=${worktree} state=${state}"
  [[ -n ${reason} ]] && line+=" reason=${reason}"
  [[ -n ${pushed} ]] && line+=" pushed=${pushed}"
  [[ -n ${drift} ]] && line+=" flake-lock-drift=${drift}"
  log_line "${line}"
}

record_orphan() {
  local path reason
  path="$1"
  reason="$2"
  orphan_records+=("${path}"$'\t'"${reason}")
  count_orphans=$((count_orphans + 1))
  log_line "orphan=${path} reason=${reason}"
}

canonical() {
  readlink -f -- "$1"
}

is_under_roots() {
  local path root canon_root
  path="$1"
  for root in "${roots[@]}"; do
    canon_root="$(canonical "${root}" 2>/dev/null)" || continue
    if [[ ${path} == "${canon_root}"/* ]]; then
      return 0
    fi
  done
  return 1
}

branch_matches_filters() {
  local branch glob matched
  branch="$1"
  if [[ ${#include_globs[@]} -gt 0 ]]; then
    matched=false
    for glob in "${include_globs[@]}"; do
      # shellcheck disable=SC2053 # glob matching is intentional
      if [[ ${branch} == ${glob} ]]; then
        matched=true
        break
      fi
    done
    ${matched} || return 1
  fi
  for glob in "${exclude_globs[@]}"; do
    # shellcheck disable=SC2053 # glob matching is intentional
    if [[ ${branch} == ${glob} ]]; then
      return 1
    fi
  done
  return 0
}

# Discovery: map worktree directories under the roots to their owning
# repositories (the main worktree that holds the shared .git directory).
declare -A repo_set=()

register_worktree_dir() {
  local dir common_dir owner
  dir="$1"
  if ! common_dir="$(git -C "${dir}" rev-parse --git-common-dir 2>/dev/null)"; then
    record_orphan "${dir}" broken-gitdir
    return
  fi
  if [[ ${common_dir} != /* ]]; then
    common_dir="${dir}/${common_dir}"
  fi
  common_dir="$(canonical "${common_dir}")"
  owner="$(dirname "${common_dir}")"
  if [[ "$(basename "${common_dir}")" != ".git" ]]; then
    # Bare repository or unusual layout; branch cleanup still works from the
    # git directory itself, worktree removal is guarded per candidate.
    owner="${common_dir}"
  fi
  repo_set["${owner}"]=1
}

scan_roots() {
  local root canon_root level1 level2 found_worktree
  for root in "${roots[@]}"; do
    canon_root="$(canonical "${root}" 2>/dev/null)" || {
      error_msg "root does not exist, skipping: ${root}"
      continue
    }
    for level1 in "${canon_root}"/*/; do
      [[ -d ${level1} ]] || continue
      level1="${level1%/}"
      if [[ -e "${level1}/.git" ]]; then
        register_worktree_dir "${level1}"
        continue
      fi
      found_worktree=false
      for level2 in "${level1}"/*/; do
        [[ -d ${level2} ]] || continue
        level2="${level2%/}"
        if [[ -e "${level2}/.git" ]]; then
          register_worktree_dir "${level2}"
          found_worktree=true
        else
          record_orphan "${level2}" not-a-worktree
        fi
      done
      # Containers without any worktree are left alone; their contents were
      # already reported as orphans.
      ${found_worktree} || true
    done
  done
}

scan_roots

for extra in ${extra_repos[@]+"${extra_repos[@]}"}; do
  if ! canon="$(canonical "${extra}" 2>/dev/null)" || [[ ! -d ${canon} ]]; then
    record_repo "${extra}" missing
    count_blocked=$((count_blocked + 1))
    continue
  fi
  if ! git -C "${canon}" rev-parse --git-dir >/dev/null 2>&1; then
    record_repo "${canon}" not-a-repo
    count_blocked=$((count_blocked + 1))
    continue
  fi
  repo_set["${canon}"]=1
done

# Per-repo working state, populated by load_repo_state.
declare -A pre_fetch_sha=()
declare -A branch_worktree=()
declare -A worktree_locked=()
main_worktree=""
main_branch=""

snapshot_remote_refs() {
  local repo line
  pre_fetch_sha=()
  while IFS= read -r line; do
    [[ -n ${line} ]] || continue
    pre_fetch_sha["${line%% *}"]="${line#* }"
  done < <(git -C "$1" for-each-ref --format='%(refname:short) %(objectname)' refs/remotes)
}

load_worktree_map() {
  local repo entry current_path first
  repo="$1"
  branch_worktree=()
  worktree_locked=()
  main_worktree=""
  main_branch=""
  current_path=""
  first=true
  while IFS= read -r -d '' entry; do
    case "${entry}" in
    worktree\ *)
      current_path="$(canonical "${entry#worktree }")"
      if ${first}; then
        main_worktree="${current_path}"
        first=false
      fi
      ;;
    branch\ refs/heads/*)
      branch_worktree["${entry#branch refs/heads/}"]="${current_path}"
      if [[ ${current_path} == "${main_worktree}" ]]; then
        main_branch="${entry#branch refs/heads/}"
      fi
      ;;
    locked*)
      worktree_locked["${current_path}"]=1
      ;;
    esac
  done < <(git -C "${repo}" worktree list --porcelain -z)
}

default_branch_of() {
  local repo head_ref
  if head_ref="$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${head_ref#refs/remotes/origin/}"
  fi
}

create_backup_ref() {
  local repo branch tip
  repo="$1"
  branch="$2"
  tip="$3"
  git -C "${repo}" update-ref "refs/prune-backup/${branch}/${now_epoch}" "${tip}"
}

expire_backup_refs() {
  local repo refname epoch cutoff
  repo="$1"
  [[ ${backup_retention_days} -gt 0 ]] || return 0
  cutoff=$((now_epoch - backup_retention_days * 86400))
  while IFS= read -r refname; do
    [[ -n ${refname} ]] || continue
    epoch="${refname##*/}"
    [[ ${epoch} =~ ^[0-9]+$ ]] || continue
    if [[ ${epoch} -lt ${cutoff} ]]; then
      git -C "${repo}" update-ref -d "${refname}" || return 1
      count_backups_expired=$((count_backups_expired + 1))
      log_line "backup-expired=${refname} repo=${repo}"
    fi
  done < <(git -C "${repo}" for-each-ref --format='%(refname)' refs/prune-backup)
}

# classify_worktree_status <worktree>
# Sets status_class to clean | flake-lock-only | dirty.
classify_worktree_status() {
  local worktree status line xy path
  worktree="$1"
  if ! status="$(git -C "${worktree}" status --porcelain=v1 --untracked-files=normal 2>/dev/null)"; then
    # A worktree whose state cannot be read is skip-and-report, not a crash.
    status_class=dirty
    return
  fi
  if [[ -z ${status} ]]; then
    status_class=clean
    return
  fi
  if [[ "$(wc -l <<<"${status}")" -eq 1 ]]; then
    line="${status}"
    xy="${line:0:2}"
    path="${line:3}"
    if [[ ${path} == "flake.lock" && ${xy} =~ ^[\ MD][\ MD]$ && ${xy} != "  " ]]; then
      status_class=flake-lock-only
      return
    fi
  fi
  status_class=dirty
}

discard_flake_lock_drift() {
  # Scoped discard explicitly requested by issue #201: flake.lock as the sole
  # dirty path in a stale worktree is disposable lockfile drift.
  git -C "$1" restore --source=HEAD --staged --worktree -- flake.lock
}

stash_dirty_state() {
  local worktree branch
  worktree="$1"
  branch="$2"
  git -C "${worktree}" stash push --include-untracked \
    -m "prune-stale-worktrees: ${branch} $(date -u +%Y%m%dT%H%M%SZ)" >/dev/null
}

remove_worktree_via_helper() {
  local repo worktree
  repo="$1"
  worktree="$2"
  helper_output="$(cd "${repo}" && "${remove_helper}" "${worktree}" 2>&1)"
}

remove_empty_container() {
  local parent
  parent="$(dirname "$1")"
  if is_under_roots "${parent}" && [[ -d ${parent} && -z "$(ls -A "${parent}")" ]]; then
    rmdir "${parent}"
    log_line "removed-empty-dir=${parent}"
  fi
}

delete_branch() {
  local repo branch tip
  repo="$1"
  branch="$2"
  tip="$3"
  # The explicit return keeps the backup mandatory even when this function
  # runs in an if-condition context where errexit is suspended.
  create_backup_ref "${repo}" "${branch}" "${tip}" || return 1
  git -C "${repo}" branch -q -D "${branch}"
}

process_branch() {
  local repo branch upstream tip worktree pushed drift reason status_class
  repo="$1"
  branch="$2"
  upstream="$3"
  tip="$4"

  worktree="${branch_worktree[${branch}]:-none}"
  drift=""

  if [[ -n ${pre_fetch_sha[${upstream}]:-} ]]; then
    if [[ ${pre_fetch_sha[${upstream}]} == "${tip}" ]]; then
      pushed=verified
    else
      pushed=unpushed
    fi
  else
    pushed=unverified
  fi

  if ! branch_matches_filters "${branch}"; then
    record_branch "${repo}" "${branch}" "${worktree}" skipped excluded "${pushed}" ""
    return
  fi

  if [[ ${branch} == main || ${branch} == master || ${branch} == "${repo_default_branch}" ]]; then
    record_branch "${repo}" "${branch}" "${worktree}" skipped protected "${pushed}" ""
    return
  fi

  if [[ ${branch} == "${main_branch}" || ${worktree} == "${main_worktree}" ]]; then
    record_branch "${repo}" "${branch}" "${worktree}" skipped checked-out "${pushed}" ""
    return
  fi

  if [[ ${pushed} == unpushed && ${mode} != force ]]; then
    record_branch "${repo}" "${branch}" "${worktree}" skipped unpushed "${pushed}" ""
    count_blocked=$((count_blocked + 1))
    return
  fi

  if [[ ${worktree} != none ]]; then
    if ! is_under_roots "${worktree}"; then
      record_branch "${repo}" "${branch}" "${worktree}" skipped outside-roots "${pushed}" ""
      count_blocked=$((count_blocked + 1))
      return
    fi
    if [[ -n ${worktree_locked[${worktree}]:-} ]]; then
      record_branch "${repo}" "${branch}" "${worktree}" skipped locked "${pushed}" ""
      count_blocked=$((count_blocked + 1))
      return
    fi
    if [[ ! -d ${worktree} ]]; then
      # Registration survives but the directory is gone; branch-only cleanup,
      # 'git worktree prune' clears the stale registration afterwards.
      worktree=missing
    fi
  fi

  if [[ ${worktree} != none && ${worktree} != missing ]]; then
    classify_worktree_status "${worktree}"
    case "${status_class}" in
    flake-lock-only)
      drift=present
      ;;
    dirty)
      if [[ ${mode} != force ]]; then
        record_branch "${repo}" "${branch}" "${worktree}" skipped dirty "${pushed}" ""
        count_blocked=$((count_blocked + 1))
        return
      fi
      ;;
    esac

    if [[ ${mode} == dry-run ]]; then
      record_branch "${repo}" "${branch}" "${worktree}" would-remove "" "${pushed}" "${drift}"
      count_would_remove=$((count_would_remove + 1))
      return
    fi

    if [[ ${status_class} == flake-lock-only ]]; then
      if ! discard_flake_lock_drift "${worktree}"; then
        record_branch "${repo}" "${branch}" "${worktree}" skipped flake-lock-restore-failed "${pushed}" "${drift}"
        count_blocked=$((count_blocked + 1))
        return
      fi
      drift=discarded
    elif [[ ${status_class} == dirty ]]; then
      if ! stash_dirty_state "${worktree}" "${branch}"; then
        record_branch "${repo}" "${branch}" "${worktree}" skipped stash-failed "${pushed}" ""
        count_blocked=$((count_blocked + 1))
        return
      fi
    fi

    if ! remove_worktree_via_helper "${repo}" "${worktree}"; then
      error_msg "helper refused ${worktree}: ${helper_output}"
      record_branch "${repo}" "${branch}" "${worktree}" skipped helper-refused "${pushed}" "${drift}"
      count_blocked=$((count_blocked + 1))
      return
    fi
    remove_empty_container "${worktree}"
  elif [[ ${mode} == dry-run ]]; then
    record_branch "${repo}" "${branch}" "${worktree}" would-remove "" "${pushed}" ""
    count_would_remove=$((count_would_remove + 1))
    return
  fi

  if ! delete_branch "${repo}" "${branch}" "${tip}"; then
    record_branch "${repo}" "${branch}" "${worktree}" skipped branch-delete-failed "${pushed}" "${drift}"
    count_blocked=$((count_blocked + 1))
    return
  fi
  record_branch "${repo}" "${branch}" "${worktree}" removed "" "${pushed}" "${drift}"
  count_removed=$((count_removed + 1))
}

process_repo() {
  local repo line branch upstream track tip
  repo="$1"

  snapshot_remote_refs "${repo}"

  local fetch_err
  if ! fetch_err="$(git -C "${repo}" fetch --all --prune --quiet 2>&1)"; then
    error_msg "fetch failed for ${repo}: ${fetch_err}"
    record_repo "${repo}" failed
    count_blocked=$((count_blocked + 1))
    return
  fi
  record_repo "${repo}" ok

  load_worktree_map "${repo}"
  repo_default_branch="$(default_branch_of "${repo}")"

  # %1f (unit separator) keeps empty fields intact; tab would collapse as
  # IFS whitespace and shift fields for branches without an upstream.
  while IFS=$'\x1f' read -r branch upstream track tip; do
    [[ -n ${branch} ]] || continue
    if [[ ${track} != "[gone]" ]]; then
      if [[ -n ${upstream} ]]; then
        count_still_remote=$((count_still_remote + 1))
      else
        count_no_upstream=$((count_no_upstream + 1))
      fi
      continue
    fi
    process_branch "${repo}" "${branch}" "${upstream}" "${tip}"
  done < <(git -C "${repo}" for-each-ref \
    --format='%(refname:short)%1f%(upstream:short)%1f%(upstream:track)%1f%(objectname)' refs/heads)

  if [[ ${mode} != dry-run ]]; then
    if ! git -C "${repo}" worktree prune; then
      error_msg "worktree prune failed for ${repo}"
      count_blocked=$((count_blocked + 1))
    fi
    if ! expire_backup_refs "${repo}"; then
      error_msg "backup ref expiry failed for ${repo}"
      count_blocked=$((count_blocked + 1))
    fi
  fi
}

if [[ ${#repo_set[@]} -eq 0 ]]; then
  error_msg "no repositories found under: ${roots[*]}"
fi

for repo_path in "${!repo_set[@]}"; do
  process_repo "${repo_path}"
done

summary_line="summary mode=${mode} removed=${count_removed} would-remove=${count_would_remove}"
summary_line+=" blocked=${count_blocked} orphans=${count_orphans}"
summary_line+=" still-remote=${count_still_remote} no-upstream=${count_no_upstream}"
summary_line+=" backups-expired=${count_backups_expired}"
log_line "${summary_line}"

if ${json_output}; then
  repos_tsv="$(printf '%s\n' ${repo_records[@]+"${repo_records[@]}"})"
  branches_tsv="$(printf '%s\n' ${branch_records[@]+"${branch_records[@]}"})"
  orphans_tsv="$(printf '%s\n' ${orphan_records[@]+"${orphan_records[@]}"})"
  jq -n \
    --arg mode "${mode}" \
    --arg repos "${repos_tsv}" \
    --arg branches "${branches_tsv}" \
    --arg orphans "${orphans_tsv}" \
    --argjson summary "{
      \"removed\": ${count_removed},
      \"wouldRemove\": ${count_would_remove},
      \"blocked\": ${count_blocked},
      \"orphans\": ${count_orphans},
      \"stillRemote\": ${count_still_remote},
      \"noUpstream\": ${count_no_upstream},
      \"backupsExpired\": ${count_backups_expired}
    }" '
    def rows($s): $s | split("\n") | map(select(length > 0) | split("\t"));
    def opt($v): if $v == "" then null else $v end;
    {
      version: 1,
      mode: $mode,
      repos: (rows($repos) | map(. as $r | {
        path: $r[0],
        fetch: $r[1],
        branches: (rows($branches) | map(select(.[0] == $r[0]) | {
          branch: .[1],
          worktree: (if .[2] == "none" then null else .[2] end),
          state: .[3],
          reason: opt(.[4]),
          pushed: opt(.[5]),
          flakeLockDrift: opt(.[6])
        }))
      })),
      orphans: (rows($orphans) | map({path: .[0], reason: .[1]})),
      summary: $summary
    }'
fi

if [[ ${mode} != dry-run && ${count_blocked} -gt 0 ]]; then
  exit 2
fi
exit 0
