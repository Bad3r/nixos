#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/prune-stale-worktrees.sh"

if [[ ! -x ${SUT} ]]; then
  printf 'run.sh: SUT not executable at %s\n' "${SUT}" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    chmod -R u+w "${tmpdir}"
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

# Isolate from the operator's real environment and git configuration.
export HOME="${tmpdir}/home"
mkdir -p "${HOME}"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0

tests_passed=0

pass() {
  tests_passed=$((tests_passed + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -n ${2:-} && -f ${2:-} ]]; then
    printf '%s\n' '--- SUT output ---' >&2
    cat "$2" >&2
    printf '%s\n' '------------------' >&2
  fi
  exit 1
}

init_repo_config() {
  git -C "$1" config user.email tests@example.invalid
  git -C "$1" config user.name "prune-stale-worktrees tests"
}

# make_fixture <name>
# Creates a bare origin, a clone acting as the primary checkout, and a
# worktree root. Sets globals: origin, repo, root.
make_fixture() {
  local name seed
  name="$1"
  seed="${tmpdir}/${name}-seed"
  origin="${tmpdir}/${name}-origin.git"
  repo="${tmpdir}/${name}-repo"
  root="${tmpdir}/${name}-trees"

  git init -q -b main "${seed}"
  init_repo_config "${seed}"
  printf '%s\n' readme >"${seed}/README.md"
  printf '%s\n' '{"nodes":{}}' >"${seed}/flake.lock"
  git -C "${seed}" add .
  git -C "${seed}" commit -q -m "initial commit"
  git clone -q --bare "${seed}" "${origin}"
  git clone -q "${origin}" "${repo}"
  init_repo_config "${repo}"
  mkdir -p "${root}"
}

# add_worktree_branch <branch> <worktree-path> [push]
# Creates <branch> in ${repo} checked out at <worktree-path>.
add_worktree_branch() {
  local branch worktree push
  branch="$1"
  worktree="$2"
  push="${3:-push}"

  mkdir -p "$(dirname "${worktree}")"
  git -C "${repo}" worktree add -q -b "${branch}" "${worktree}"
  if [[ ${push} == push ]]; then
    git -C "${worktree}" push -q -u origin "${branch}"
  fi
}

# delete_on_origin <branch>
# Deletes the branch on the bare origin without touching the clone's
# remote-tracking refs, mimicking a remote-side deletion after PR merge.
delete_on_origin() {
  git -C "${origin}" update-ref -d "refs/heads/$1"
}

# run_sut <output-file> <args...>
run_sut() {
  local out
  out="$1"
  shift
  if "${SUT}" "$@" >"${out}" 2>&1; then
    sut_status=0
  else
    sut_status=$?
  fi
}

assert_contains() {
  local file pattern label
  file="$1"
  pattern="$2"
  label="$3"
  if ! grep -Eq "${pattern}" "${file}"; then
    fail "${label}: output does not match '${pattern}'" "${file}"
  fi
}

assert_not_contains() {
  local file pattern label
  file="$1"
  pattern="$2"
  label="$3"
  if grep -Eq "${pattern}" "${file}"; then
    fail "${label}: output unexpectedly matches '${pattern}'" "${file}"
  fi
}

assert_branch_exists() {
  git -C "${repo}" show-ref --verify --quiet "refs/heads/$1" ||
    fail "$2: branch $1 missing"
}

assert_branch_absent() {
  ! git -C "${repo}" show-ref --verify --quiet "refs/heads/$1" ||
    fail "$2: branch $1 still exists"
}

assert_dir_exists() {
  [[ -d $1 ]] || fail "$2: directory $1 missing"
}

assert_dir_absent() {
  [[ ! -e $1 ]] || fail "$2: directory $1 still exists"
}

assert_backup_ref() {
  local branch expected_sha label refs
  branch="$1"
  expected_sha="$2"
  label="$3"
  refs="$(git -C "${repo}" for-each-ref --format='%(objectname)' "refs/prune-backup/${branch}/**")"
  if [[ -z ${refs} ]]; then
    refs="$(git -C "${repo}" for-each-ref --format='%(objectname)' "refs/prune-backup/${branch}/*")"
  fi
  [[ -n ${refs} ]] || fail "${label}: no backup ref for ${branch}"
  if [[ -n ${expected_sha} ]]; then
    grep -q "${expected_sha}" <<<"${refs}" ||
      fail "${label}: backup ref for ${branch} does not point at ${expected_sha}"
  fi
}

test_dry_run_reports_and_preserves() {
  local out wt
  make_fixture dryrun
  wt="${root}/proj/feat-alpha"
  add_worktree_branch feat/alpha "${wt}"
  delete_on_origin feat/alpha

  out="${tmpdir}/dryrun.out"
  run_sut "${out}" --root "${root}"

  [[ ${sut_status} -eq 0 ]] || fail "dry-run: expected exit 0, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/alpha .*state=would-remove" "dry-run"
  assert_dir_exists "${wt}" "dry-run"
  assert_branch_exists feat/alpha "dry-run"
  pass
}

test_apply_removes_branch_worktree_and_backs_up() {
  local out wt tip
  make_fixture apply
  wt="${root}/proj/feat-alpha"
  add_worktree_branch feat/alpha "${wt}"
  tip="$(git -C "${repo}" rev-parse refs/heads/feat/alpha)"
  delete_on_origin feat/alpha

  out="${tmpdir}/apply.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 0 ]] || fail "apply: expected exit 0, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/alpha .*state=removed" "apply"
  assert_dir_absent "${wt}" "apply"
  assert_dir_absent "${root}/proj" "apply: empty container should be removed"
  assert_branch_absent feat/alpha "apply"
  assert_backup_ref feat/alpha "${tip}" "apply"
  pass
}

test_protects_master_branch() {
  local out
  make_fixture protected
  git -C "${repo}" branch master
  git -C "${repo}" push -q -u origin master
  delete_on_origin master

  out="${tmpdir}/protected.out"
  run_sut "${out}" --repo "${repo}" --root "${root}" --apply

  assert_branch_exists master "protected"
  assert_contains "${out}" "branch=master .*state=skipped .*reason=protected" "protected"
  pass
}

test_protects_branch_checked_out_in_primary_worktree() {
  local out
  make_fixture checkedout
  git -C "${repo}" switch -q -c feat/current
  git -C "${repo}" push -q -u origin feat/current
  delete_on_origin feat/current

  out="${tmpdir}/checkedout.out"
  run_sut "${out}" --repo "${repo}" --root "${root}" --apply

  assert_branch_exists feat/current "checked-out"
  assert_contains "${out}" "branch=feat/current .*state=skipped .*reason=checked-out" "checked-out"
  pass
}

test_skips_unpushed_commits_without_force() {
  local out wt
  make_fixture unpushed
  wt="${root}/proj/feat-gamma"
  add_worktree_branch feat/gamma "${wt}"
  printf '%s\n' extra >"${wt}/extra.txt"
  git -C "${wt}" add extra.txt
  git -C "${wt}" commit -q -m "unpushed work"
  delete_on_origin feat/gamma

  out="${tmpdir}/unpushed.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 2 ]] || fail "unpushed: expected exit 2, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/gamma .*state=skipped .*reason=unpushed" "unpushed"
  assert_dir_exists "${wt}" "unpushed"
  assert_branch_exists feat/gamma "unpushed"
  pass
}

test_force_removes_unpushed_with_backup() {
  local out wt tip
  make_fixture forceunpushed
  wt="${root}/proj/feat-gamma"
  add_worktree_branch feat/gamma "${wt}"
  printf '%s\n' extra >"${wt}/extra.txt"
  git -C "${wt}" add extra.txt
  git -C "${wt}" commit -q -m "unpushed work"
  tip="$(git -C "${repo}" rev-parse refs/heads/feat/gamma)"
  delete_on_origin feat/gamma

  out="${tmpdir}/forceunpushed.out"
  run_sut "${out}" --root "${root}" --force

  [[ ${sut_status} -eq 0 ]] || fail "force-unpushed: expected exit 0, got ${sut_status}" "${out}"
  assert_dir_absent "${wt}" "force-unpushed"
  assert_branch_absent feat/gamma "force-unpushed"
  assert_backup_ref feat/gamma "${tip}" "force-unpushed"
  pass
}

test_skips_dirty_worktree_without_force() {
  local out wt
  make_fixture dirty
  wt="${root}/proj/feat-delta"
  add_worktree_branch feat/delta "${wt}"
  printf '%s\n' modified >"${wt}/README.md"
  delete_on_origin feat/delta

  out="${tmpdir}/dirty.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 2 ]] || fail "dirty: expected exit 2, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/delta .*state=skipped .*reason=dirty" "dirty"
  assert_dir_exists "${wt}" "dirty"
  assert_branch_exists feat/delta "dirty"
  pass
}

test_force_stashes_dirty_and_removes() {
  local out wt
  make_fixture forcedirty
  wt="${root}/proj/feat-delta"
  add_worktree_branch feat/delta "${wt}"
  printf '%s\n' modified >"${wt}/README.md"
  printf '%s\n' untracked >"${wt}/scratch.txt"
  delete_on_origin feat/delta

  out="${tmpdir}/forcedirty.out"
  run_sut "${out}" --root "${root}" --force

  [[ ${sut_status} -eq 0 ]] || fail "force-dirty: expected exit 0, got ${sut_status}" "${out}"
  assert_dir_absent "${wt}" "force-dirty"
  assert_branch_absent feat/delta "force-dirty"
  git -C "${repo}" stash list | grep -q "prune-stale-worktrees: feat/delta" ||
    fail "force-dirty: no stash entry preserving dirty state" "${out}"
  pass
}

test_flake_lock_only_drift_is_discarded_in_safe_apply() {
  local out wt
  make_fixture flakelock
  wt="${root}/proj/feat-epsilon"
  add_worktree_branch feat/epsilon "${wt}"
  printf '%s\n' '{"nodes":{"drift":true}}' >"${wt}/flake.lock"
  delete_on_origin feat/epsilon

  out="${tmpdir}/flakelock.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 0 ]] || fail "flake-lock: expected exit 0, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/epsilon .*state=removed .*flake-lock-drift=discarded" "flake-lock"
  assert_dir_absent "${wt}" "flake-lock"
  assert_branch_absent feat/epsilon "flake-lock"
  pass
}

test_flake_lock_plus_other_dirt_is_skipped() {
  local out wt
  make_fixture flakelockmixed
  wt="${root}/proj/feat-zeta"
  add_worktree_branch feat/zeta "${wt}"
  printf '%s\n' '{"nodes":{"drift":true}}' >"${wt}/flake.lock"
  printf '%s\n' modified >"${wt}/README.md"
  delete_on_origin feat/zeta

  out="${tmpdir}/flakelockmixed.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 2 ]] || fail "flake-lock-mixed: expected exit 2, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/zeta .*state=skipped .*reason=dirty" "flake-lock-mixed"
  assert_dir_exists "${wt}" "flake-lock-mixed"
  assert_branch_exists feat/zeta "flake-lock-mixed"
  pass
}

test_gone_branch_without_worktree_is_deleted() {
  local out tip
  make_fixture branchonly
  git -C "${repo}" branch feat/eta
  git -C "${repo}" push -q -u origin feat/eta
  tip="$(git -C "${repo}" rev-parse refs/heads/feat/eta)"
  delete_on_origin feat/eta

  out="${tmpdir}/branchonly.out"
  run_sut "${out}" --repo "${repo}" --root "${root}" --apply

  [[ ${sut_status} -eq 0 ]] || fail "branch-only: expected exit 0, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/eta .*worktree=none .*state=removed" "branch-only"
  assert_branch_absent feat/eta "branch-only"
  assert_backup_ref feat/eta "${tip}" "branch-only"
  pass
}

test_still_remote_and_no_upstream_branches_untouched() {
  local out
  make_fixture untouched
  git -C "${repo}" branch feat/alive
  git -C "${repo}" push -q -u origin feat/alive
  git -C "${repo}" branch feat/local-only

  out="${tmpdir}/untouched.out"
  run_sut "${out}" --repo "${repo}" --root "${root}" --apply

  [[ ${sut_status} -eq 0 ]] || fail "untouched: expected exit 0, got ${sut_status}" "${out}"
  assert_branch_exists feat/alive "untouched"
  assert_branch_exists feat/local-only "untouched"
  # main + feat/alive track a live upstream; feat/local-only has none.
  assert_contains "${out}" "summary .*still-remote=2 no-upstream=1" "untouched"
  assert_not_contains "${out}" "branch=feat/alive .*state=(removed|would-remove|skipped)" "untouched"
  assert_not_contains "${out}" "branch=feat/local-only .*state=(removed|would-remove|skipped)" "untouched"
  pass
}

test_already_gone_upstream_removed_with_unverified_backup() {
  local out wt tip
  make_fixture alreadygone
  wt="${root}/proj/feat-theta"
  add_worktree_branch feat/theta "${wt}"
  tip="$(git -C "${repo}" rev-parse refs/heads/feat/theta)"
  delete_on_origin feat/theta
  git -C "${repo}" fetch -q --prune origin

  out="${tmpdir}/alreadygone.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 0 ]] || fail "already-gone: expected exit 0, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/theta .*state=removed .*pushed=unverified" "already-gone"
  assert_dir_absent "${wt}" "already-gone"
  assert_branch_absent feat/theta "already-gone"
  assert_backup_ref feat/theta "${tip}" "already-gone"
  pass
}

test_helper_is_final_arbiter_for_ignored_state() {
  local out wt
  make_fixture ignoredstate
  wt="${root}/proj/feat-iota"
  printf '%s\n' '*.key' >"${repo}/.gitignore"
  git -C "${repo}" add .gitignore
  git -C "${repo}" commit -q -m "ignore key files"
  git -C "${repo}" push -q origin main
  add_worktree_branch feat/iota "${wt}"
  printf '%s\n' secret >"${wt}/local.key"
  delete_on_origin feat/iota

  out="${tmpdir}/ignoredstate.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 2 ]] || fail "ignored-state: expected exit 2, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/iota .*state=skipped .*reason=helper-refused" "ignored-state"
  assert_dir_exists "${wt}" "ignored-state"
  assert_branch_exists feat/iota "ignored-state"
  pass
}

test_multiple_roots_are_scanned() {
  local out wt1 repo1 root1 wt2
  make_fixture multiroot1
  repo1="${repo}"
  root1="${root}"
  wt1="${root1}/proj/feat-kappa"
  add_worktree_branch feat/kappa "${wt1}"
  delete_on_origin feat/kappa

  make_fixture multiroot2
  wt2="${root}/proj/feat-lambda"
  add_worktree_branch feat/lambda "${wt2}"
  delete_on_origin feat/lambda

  out="${tmpdir}/multiroot.out"
  run_sut "${out}" --root "${root1}" --root "${root}" --apply

  [[ ${sut_status} -eq 0 ]] || fail "multi-root: expected exit 0, got ${sut_status}" "${out}"
  assert_dir_absent "${wt1}" "multi-root"
  assert_dir_absent "${wt2}" "multi-root"
  git -C "${repo1}" show-ref --verify --quiet refs/heads/feat/kappa &&
    fail "multi-root: feat/kappa still exists" "${out}"
  assert_branch_absent feat/lambda "multi-root"
  pass
}

test_orphan_directories_reported_not_deleted() {
  local out wt orphan_plain orphan_broken
  make_fixture orphans
  wt="${root}/proj/feat-mu"
  add_worktree_branch feat/mu "${wt}"
  orphan_plain="${root}/proj/not-a-worktree"
  mkdir -p "${orphan_plain}"
  printf '%s\n' data >"${orphan_plain}/file.txt"
  orphan_broken="${root}/proj/broken-gitdir"
  mkdir -p "${orphan_broken}"
  printf 'gitdir: %s\n' "${tmpdir}/nonexistent/.git/worktrees/broken" >"${orphan_broken}/.git"

  out="${tmpdir}/orphans.out"
  run_sut "${out}" --root "${root}" --apply

  assert_contains "${out}" "orphan=${orphan_plain}" "orphans"
  assert_contains "${out}" "orphan=${orphan_broken}" "orphans"
  assert_dir_exists "${orphan_plain}" "orphans"
  assert_dir_exists "${orphan_broken}" "orphans"
  pass
}

test_backup_refs_expire_after_retention() {
  local out old_epoch head_sha
  make_fixture expiry
  head_sha="$(git -C "${repo}" rev-parse HEAD)"
  old_epoch=$(($(date +%s) - 90 * 24 * 3600))
  git -C "${repo}" update-ref "refs/prune-backup/feat/old/${old_epoch}" "${head_sha}"
  git -C "${repo}" update-ref "refs/prune-backup/feat/fresh/$(date +%s)" "${head_sha}"

  out="${tmpdir}/expiry.out"
  run_sut "${out}" --repo "${repo}" --root "${root}" --apply --backup-retention-days 30

  if git -C "${repo}" show-ref --verify --quiet "refs/prune-backup/feat/old/${old_epoch}"; then
    fail "expiry: expired backup ref survived" "${out}"
  fi
  [[ -n "$(git -C "${repo}" for-each-ref "refs/prune-backup/feat/fresh")" ]] ||
    fail "expiry: fresh backup ref was expired" "${out}"
  pass
}

test_backup_failure_blocks_branch_deletion() {
  local out head_sha
  make_fixture backupfail
  git -C "${repo}" branch feat/rho
  git -C "${repo}" push -q -u origin feat/rho
  delete_on_origin feat/rho
  # A ref at the exact directory prefix makes refs/prune-backup/feat/rho/<epoch>
  # unwritable, forcing the backup step to fail.
  head_sha="$(git -C "${repo}" rev-parse HEAD)"
  git -C "${repo}" update-ref refs/prune-backup/feat/rho "${head_sha}"

  out="${tmpdir}/backupfail.out"
  run_sut "${out}" --repo "${repo}" --root "${root}" --apply

  [[ ${sut_status} -eq 2 ]] || fail "backup-fail: expected exit 2, got ${sut_status}" "${out}"
  assert_contains "${out}" "branch=feat/rho .*state=skipped .*reason=branch-delete-failed" "backup-fail"
  assert_branch_exists feat/rho "backup-fail"
  pass
}

test_fetch_failure_skips_repo() {
  local out wt
  make_fixture fetchfail
  wt="${root}/proj/feat-nu"
  add_worktree_branch feat/nu "${wt}"
  delete_on_origin feat/nu
  git -C "${repo}" remote set-url origin "${tmpdir}/no-such-origin.git"

  out="${tmpdir}/fetchfail.out"
  run_sut "${out}" --root "${root}" --apply

  [[ ${sut_status} -eq 2 ]] || fail "fetch-fail: expected exit 2, got ${sut_status}" "${out}"
  assert_contains "${out}" "repo=${repo} fetch=failed" "fetch-fail"
  assert_dir_exists "${wt}" "fetch-fail"
  assert_branch_exists feat/nu "fetch-fail"
  pass
}

test_exclude_pattern_limits_candidates() {
  local out wt1 wt2
  make_fixture patterns
  wt1="${root}/proj/feat-xi"
  wt2="${root}/proj/fix-omicron"
  add_worktree_branch feat/xi "${wt1}"
  add_worktree_branch fix/omicron "${wt2}"
  delete_on_origin feat/xi
  delete_on_origin fix/omicron

  out="${tmpdir}/patterns.out"
  run_sut "${out}" --root "${root}" --apply --exclude 'feat/*'

  assert_branch_exists feat/xi "patterns"
  assert_dir_exists "${wt1}" "patterns"
  assert_branch_absent fix/omicron "patterns"
  assert_dir_absent "${wt2}" "patterns"
  pass
}

test_json_output_is_valid() {
  local out wt
  make_fixture json
  wt="${root}/proj/feat-pi"
  add_worktree_branch feat/pi "${wt}"
  delete_on_origin feat/pi

  out="${tmpdir}/json.out"
  run_sut "${out}" --root "${root}" --json

  [[ ${sut_status} -eq 0 ]] || fail "json: expected exit 0, got ${sut_status}" "${out}"
  jq -e '.mode == "dry-run"' <"${out}" >/dev/null || fail "json: missing mode" "${out}"
  jq -e '[.repos[].branches[] | select(.branch == "feat/pi" and .state == "would-remove")] | length == 1' \
    <"${out}" >/dev/null || fail "json: candidate entry missing" "${out}"
  assert_dir_exists "${wt}" "json"
  pass
}

test_dry_run_reports_and_preserves
test_apply_removes_branch_worktree_and_backs_up
test_protects_master_branch
test_protects_branch_checked_out_in_primary_worktree
test_skips_unpushed_commits_without_force
test_force_removes_unpushed_with_backup
test_skips_dirty_worktree_without_force
test_force_stashes_dirty_and_removes
test_flake_lock_only_drift_is_discarded_in_safe_apply
test_flake_lock_plus_other_dirt_is_skipped
test_gone_branch_without_worktree_is_deleted
test_still_remote_and_no_upstream_branches_untouched
test_already_gone_upstream_removed_with_unverified_backup
test_helper_is_final_arbiter_for_ignored_state
test_multiple_roots_are_scanned
test_orphan_directories_reported_not_deleted
test_backup_refs_expire_after_retention
test_backup_failure_blocks_branch_deletion
test_fetch_failure_skips_repo
test_exclude_pattern_limits_candidates
test_json_output_is_valid

printf '%d passed\n' "${tests_passed}"
