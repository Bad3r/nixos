#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/prune-old-stashes.sh"

if [[ ! -x ${SUT} ]]; then
  printf 'run.sh: SUT not executable at %s\n' "${SUT}" >&2
  exit 2
fi

REAL_GIT="$(command -v git)"

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    chmod -R u+w "${tmpdir}"
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

# Isolate from the operator's real environment and git configuration. The lock
# lives under XDG_RUNTIME_DIR/TMPDIR, so both are redirected into the sandbox to
# keep a test run from colliding with a real one.
export HOME="${tmpdir}/home"
mkdir -p "${HOME}"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
export TMPDIR="${tmpdir}"
export XDG_RUNTIME_DIR="${tmpdir}"

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
  git -C "$1" config user.name "prune-old-stashes tests"
}

# make_fixture <name>
# Creates a repository with one commit. Sets the global `repo`.
make_fixture() {
  repo="${tmpdir}/$1"
  git init -q -b main "${repo}"
  init_repo_config "${repo}"
  printf '%s\n' base >"${repo}/f"
  git -C "${repo}" add f
  git -C "${repo}" commit -q -m "initial commit"
}

# push_stash <repo> <message> <age-days>
push_stash() {
  local repo_dir msg age when
  repo_dir="$1"
  msg="$2"
  age="$3"
  when="$(($(date +%s) - age * 86400))"
  printf '%s\n' "${msg}" >"${repo_dir}/f"
  GIT_COMMITTER_DATE="${when}" GIT_AUTHOR_DATE="${when}" \
    git -C "${repo_dir}" stash push -q -m "${msg}"
}

# run_sut <output-file> <repo> <args...>
run_sut() {
  local out repo_dir
  out="$1"
  repo_dir="$2"
  shift 2
  if (cd "${repo_dir}" && "${SUT}" "$@") >"${out}" 2>&1; then
    sut_status=0
  else
    sut_status=$?
  fi
}

assert_contains() {
  grep -Eq "$2" "$1" || fail "$3: output does not match '$2'" "$1"
}

assert_not_contains() {
  ! grep -Eq "$2" "$1" || fail "$3: output unexpectedly matches '$2'" "$1"
}

assert_status() {
  [[ ${sut_status} -eq $1 ]] || fail "$3: expected exit $1, got ${sut_status}" "$2"
}

# assert_stash_count <repo> <expected> <label>
assert_stash_count() {
  local actual
  actual="$(git -C "$1" stash list | wc -l)"
  [[ ${actual} -eq $2 ]] || fail "$3: expected $2 stashes, found ${actual}"
}

# assert_archive_count <repo> <expected> <label>
assert_archive_count() {
  local actual
  actual="$(git -C "$1" for-each-ref --format='%(refname)' 'refs/stash-archive/' | wc -l)"
  [[ ${actual} -eq $2 ]] || fail "$3: expected $2 archive refs, found ${actual}"
}

# assert_stash_subject_absent <repo> <message> <label>
assert_stash_subject_absent() {
  ! git -C "$1" stash list | grep -Fq "$2" || fail "$3: stash '$2' is still stashed"
}

# assert_stash_subject_present <repo> <message> <label>
assert_stash_subject_present() {
  git -C "$1" stash list | grep -Fq "$2" || fail "$3: stash '$2' is missing"
}

test_dry_run_reports_and_preserves() {
  local out
  make_fixture dry-run
  push_stash "${repo}" old-a 30
  push_stash "${repo}" old-b 20
  push_stash "${repo}" fresh 1
  out="${tmpdir}/dry-run.out"

  run_sut "${out}" "${repo}"
  assert_status 0 "${out}" dry-run
  assert_contains "${out}" 'would archive stash@\{2\}' dry-run
  assert_contains "${out}" 'would archive stash@\{1\}' dry-run
  assert_not_contains "${out}" 'would archive stash@\{0\}' dry-run
  assert_contains "${out}" 'dry-run: 2 stash\(es\) and 0 archive ref\(s\) selected' dry-run
  assert_stash_count "${repo}" 3 dry-run
  assert_archive_count "${repo}" 0 dry-run
  pass
}

test_apply_archives_then_drops() {
  local out
  make_fixture apply
  push_stash "${repo}" old-a 30
  push_stash "${repo}" fresh 1
  out="${tmpdir}/apply.out"

  run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" apply
  assert_contains "${out}" 'dropped stash@\{1\}' apply
  assert_stash_count "${repo}" 1 apply
  assert_stash_subject_present "${repo}" fresh apply
  assert_stash_subject_absent "${repo}" old-a apply
  assert_archive_count "${repo}" 1 apply
  pass
}

test_archived_stash_is_recoverable() {
  local out ref
  make_fixture recover
  push_stash "${repo}" recoverable-content 30
  out="${tmpdir}/recover.out"

  run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" recover
  ref="$(git -C "${repo}" for-each-ref --format='%(refname)' 'refs/stash-archive/')"
  [[ -n ${ref} ]] || fail "recover: no archive ref written"
  git -C "${repo}" stash apply "${ref}" >/dev/null 2>&1 ||
    fail "recover: git stash apply ${ref} failed"
  grep -Fqx recoverable-content "${repo}/f" ||
    fail "recover: archive ref did not restore the stashed content"
  pass
}

test_age_threshold_is_parsed_base_ten() {
  local out
  make_fixture age-base-ten
  push_stash "${repo}" nine-days 9
  out="${tmpdir}/age.out"

  # A leading zero must not be read as octal: 010 is ten days, so a nine-day
  # stash stays. Read as octal it would be eight days and the stash would go.
  run_sut "${out}" "${repo}" --age 010
  assert_status 0 "${out}" age-base-ten
  assert_contains "${out}" 'no stashes older than 10d' age-base-ten

  # 08d and 09 are not valid octal literals at all and used to abort the run.
  run_sut "${out}" "${repo}" --age 08d
  assert_status 0 "${out}" age-base-ten
  assert_contains "${out}" 'would archive stash@\{0\}' age-base-ten

  run_sut "${out}" "${repo}" --age 09
  assert_status 0 "${out}" age-base-ten
  assert_contains "${out}" 'would archive stash@\{0\}' age-base-ten

  # Weeks multiply during parsing, so the same normalization applies there.
  run_sut "${out}" "${repo}" --age 08w
  assert_status 0 "${out}" age-base-ten
  assert_contains "${out}" 'no stashes older than 56d' age-base-ten
  pass
}

test_invalid_duration_is_a_usage_error() {
  local out
  make_fixture bad-duration
  out="${tmpdir}/bad-duration.out"

  run_sut "${out}" "${repo}" --age 3months
  assert_status 64 "${out}" bad-duration
  assert_contains "${out}" "invalid duration '3months'" bad-duration
  pass
}

test_unreadable_stash_list_fails_loudly() {
  local out
  make_fixture unreadable
  push_stash "${repo}" old-a 30
  out="${tmpdir}/unreadable.out"

  # A `refs/stash` pointing at a missing object makes `git stash list` exit 1
  # with `fatal: bad object refs/stash`. Read through a process substitution
  # that failure is invisible and the repository looks clean instead.
  printf '%s\n' deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >"${repo}/.git/refs/stash"
  run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" unreadable
  assert_contains "${out}" 'ERROR: cannot read the stash list' unreadable
  assert_not_contains "${out}" 'no stashes older than' unreadable
  assert_archive_count "${repo}" 0 unreadable
  pass
}

test_unreadable_archive_refs_fail_loudly() {
  local out shim
  make_fixture archive-unreadable
  out="${tmpdir}/archive-unreadable.out"

  # `git for-each-ref` survives broken and unreadable refs, so the failure has
  # to be forced. Read through a process substitution a genuine failure would
  # be indistinguishable from a repository with nothing left to expire.
  shim="${tmpdir}/archive-unreadable-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
#!/usr/bin/env bash
if [[ " \$* " == *" for-each-ref "* && " \$* " == *"refs/stash-archive/"* ]]; then
  echo "fatal: forced for-each-ref failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --sweep-archive --apply
  assert_status 1 "${out}" archive-unreadable
  assert_contains "${out}" 'ERROR: cannot read archive refs' archive-unreadable
  pass
}

test_failed_archive_write_aborts_the_drop() {
  local out shim
  make_fixture archive-fail
  push_stash "${repo}" old-a 30
  out="${tmpdir}/archive-fail.out"

  # Half of the "never drop a stash we did not archive" guarantee: if the
  # archive ref cannot be written, the stash must survive.
  shim="${tmpdir}/archive-fail-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
#!/usr/bin/env bash
if [[ " \$* " == *" update-ref "* && " \$* " == *"refs/stash-archive/"* ]]; then
  echo "fatal: forced update-ref failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" archive-fail
  assert_contains "${out}" 'archive write failed .*NOT dropping' archive-fail
  assert_stash_subject_present "${repo}" old-a archive-fail
  assert_stash_count "${repo}" 1 archive-fail
  assert_archive_count "${repo}" 0 archive-fail
  pass
}

test_sha_mismatch_gate_blocks_the_drop() {
  local out shim
  make_fixture mismatch
  push_stash "${repo}" old-a 30
  out="${tmpdir}/mismatch.out"

  # The other half: the last gate before `git stash drop` re-resolves
  # stash@{N} and must refuse when it no longer names the archived commit.
  # The archive ref is keyed by sha and is deliberately kept.
  shim="${tmpdir}/mismatch-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
#!/usr/bin/env bash
if [[ " \$* " == *" rev-parse "* && " \$* " == *"stash@{"* ]]; then
  printf '%s\n' 1111111111111111111111111111111111111111
  exit 0
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" mismatch
  assert_contains "${out}" 'no longer resolves to' mismatch
  assert_contains "${out}" 'archive ref .* kept' mismatch
  assert_stash_subject_present "${repo}" old-a mismatch
  assert_stash_count "${repo}" 1 mismatch
  assert_archive_count "${repo}" 1 mismatch
  pass
}

test_concurrent_push_does_not_block_pruning() {
  local out shim
  make_fixture race
  push_stash "${repo}" old-a 30
  push_stash "${repo}" old-b 30
  out="${tmpdir}/race.out"

  # Shim git so that the run's snapshot listing is immediately invalidated by a
  # push from "another shell", shifting every recorded index by one.
  shim="${tmpdir}/race-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
#!/usr/bin/env bash
"${REAL_GIT}" "\$@"
rc=\$?
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* && ! -e "${tmpdir}/raced" ]]; then
  : >"${tmpdir}/raced"
  printf '%s\n' racer >"${repo}/f"
  "${REAL_GIT}" -C "${repo}" stash push -q -m racer
fi
exit \$rc
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" race
  assert_stash_count "${repo}" 1 race
  assert_stash_subject_present "${repo}" racer race
  assert_stash_subject_absent "${repo}" old-a race
  assert_stash_subject_absent "${repo}" old-b race
  assert_archive_count "${repo}" 2 race
  pass
}

test_vanished_stash_is_skipped_not_mistaken() {
  local out shim
  make_fixture vanished
  push_stash "${repo}" doomed 30
  push_stash "${repo}" keeper 30
  out="${tmpdir}/vanished.out"

  # `doomed` disappears from the stack between the snapshot and the drop loop.
  # Its recorded sha must simply not be found, never resolved to `keeper`.
  shim="${tmpdir}/vanished-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
#!/usr/bin/env bash
"${REAL_GIT}" "\$@"
rc=\$?
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* && ! -e "${tmpdir}/vanish-done" ]]; then
  : >"${tmpdir}/vanish-done"
  "${REAL_GIT}" -C "${repo}" stash drop -q "stash@{1}"
fi
exit \$rc
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" vanished
  assert_contains "${out}" 'is no longer in the stash stack' vanished
  assert_stash_count "${repo}" 0 vanished
  # `keeper` was still eligible and still present, so it is pruned normally.
  assert_archive_count "${repo}" 1 vanished
  pass
}

test_second_instance_is_locked_out() {
  local out lock
  make_fixture lock
  push_stash "${repo}" old-a 30
  out="${tmpdir}/lock.out"
  lock="${XDG_RUNTIME_DIR}/prune-old-stashes.$(id -u).lock"

  # The test shell holds the lock itself, so contention is deterministic rather
  # than a race against a background holder.
  exec 9>"${lock}"
  flock -n 9 || fail "lock: the test could not take the lock it is about to contend"

  run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" lock
  assert_contains "${out}" 'another instance is already running' lock
  assert_stash_count "${repo}" 1 lock
  assert_archive_count "${repo}" 0 lock

  exec 9>&-

  # The lock is released with the descriptor, so the next run proceeds.
  run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" lock-released
  assert_stash_count "${repo}" 0 lock-released
  pass
}

test_sweep_archive_respects_retention() {
  local out
  make_fixture sweep
  push_stash "${repo}" old-a 30
  out="${tmpdir}/sweep.out"

  run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" sweep
  assert_archive_count "${repo}" 1 sweep

  # A ref dated well before the window, standing in for an earlier run.
  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  assert_archive_count "${repo}" 2 sweep-seeded

  # Default retention is 90d: the stale ref goes, today's stays.
  run_sut "${out}" "${repo}" --sweep-archive
  assert_status 0 "${out}" sweep-dry
  assert_contains "${out}" 'would delete archive ref refs/stash-archive/2020-01-01/' sweep-dry
  # The closing summary is what an operator reads to decide whether --apply is
  # worth running; a sweep-only run must not report itself as a no-op.
  assert_contains "${out}" 'dry-run: 0 stash\(es\) and 1 archive ref\(s\) selected' sweep-dry
  assert_not_contains "${out}" "would delete archive ref refs/stash-archive/$(date -u +%F)/" sweep-dry
  assert_archive_count "${repo}" 2 sweep-dry

  run_sut "${out}" "${repo}" --sweep-archive --apply
  assert_status 0 "${out}" sweep-apply
  assert_contains "${out}" 'deleted archive ref refs/stash-archive/2020-01-01/' sweep-apply
  assert_archive_count "${repo}" 1 sweep-apply
  pass
}

test_sweep_never_deletes_this_runs_archive() {
  local out ref
  make_fixture sweep-same-run
  push_stash "${repo}" precious 30
  out="${tmpdir}/sweep-same-run.out"

  # prune_repo runs before sweep_repo, so a single invocation must never expire
  # the archive of the stash it just dropped. 1 is the most aggressive window
  # that still expires anything.
  run_sut "${out}" "${repo}" --apply --sweep-archive --archive-retention 1
  assert_status 0 "${out}" sweep-same-run
  assert_contains "${out}" 'dropped stash@\{0\}' sweep-same-run
  assert_not_contains "${out}" 'deleted archive ref' sweep-same-run
  assert_stash_count "${repo}" 0 sweep-same-run
  assert_archive_count "${repo}" 1 sweep-same-run

  # The recovery path the run advertised actually works.
  ref="$(git -C "${repo}" for-each-ref --format='%(refname)' 'refs/stash-archive/')"
  git -C "${repo}" stash apply "${ref}" >/dev/null 2>&1 ||
    fail "sweep-same-run: git stash apply ${ref} failed"
  grep -Fqx precious "${repo}/f" ||
    fail "sweep-same-run: the archive did not restore the dropped stash"
  pass
}

test_zero_retention_disables_expiry() {
  local out
  make_fixture zero-retention
  out="${tmpdir}/zero-retention.out"

  # 0 disables expiry, as it does for --backup-retention-days in
  # prune-stale-worktrees.sh. Read as a zero-length grace period instead, it
  # would delete every archive ref in the repository.
  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  git -C "${repo}" update-ref refs/stash-archive/2019-06-30/bbbbbbbbbbbb HEAD

  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 0
  assert_status 0 "${out}" zero-retention-dry
  assert_not_contains "${out}" 'would delete archive ref' zero-retention-dry
  assert_contains "${out}" 'dry-run: nothing selected' zero-retention-dry

  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 0 --apply
  assert_status 0 "${out}" zero-retention-apply
  assert_not_contains "${out}" 'deleted archive ref' zero-retention-apply
  assert_archive_count "${repo}" 2 zero-retention-apply

  # A window of 1 still expires them, so the guard is not disabling the sweep.
  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 1 --apply
  assert_status 0 "${out}" zero-retention-contrast
  assert_archive_count "${repo}" 0 zero-retention-contrast
  pass
}

test_rejected_entry_does_not_shift_reported_positions() {
  local out shim
  make_fixture bad-entry
  push_stash "${repo}" old-a 30
  push_stash "${repo}" old-b 30
  push_stash "${repo}" old-c 30
  out="${tmpdir}/bad-entry.out"

  # A malformed entry cannot be produced through git itself, so the listing's
  # first line is replaced with garbage. It still occupies stack slot 0.
  shim="${tmpdir}/bad-entry-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
#!/usr/bin/env bash
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* ]]; then
  printf 'stash@{0}||not-a-sha|garbage\n'
  "${REAL_GIT}" "\$@" | tail -n +2
  exit \${PIPESTATUS[0]}
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}"
  assert_status 1 "${out}" bad-entry
  assert_contains "${out}" 'ERROR: unparsable stash list entry' bad-entry
  # old-a really sits at stash@{2}; slots 1 and 2 must keep their numbering.
  assert_contains "${out}" 'would archive stash@\{2\}' bad-entry
  assert_contains "${out}" 'would archive stash@\{1\}' bad-entry
  assert_not_contains "${out}" 'would archive stash@\{0\}' bad-entry
  assert_stash_count "${repo}" 3 bad-entry
  pass
}

test_linked_worktrees_share_one_stash_stack() {
  local out linked trees
  trees="${HOME}/trees/nixos"
  mkdir -p "${trees}"
  make_fixture shared
  push_stash "${repo}" old-a 30
  linked="${trees}/shared-linked"
  git -C "${repo}" worktree add -q -b side "${linked}"
  out="${tmpdir}/shared.out"

  run_sut "${out}" "${linked}" --all-worktrees
  assert_status 0 "${out}" shared
  # One repo header and one selected stash, not one per root.
  [[ $(grep -c '^repo: ' "${out}") -eq 1 ]] ||
    fail "shared: shared stash stack was processed more than once" "${out}"
  assert_contains "${out}" 'dry-run: 1 stash\(es\) and 0 archive ref\(s\) selected' shared
  pass
}

test_dry_run_writes_nothing_on_a_stale_snapshot() {
  local out before
  make_fixture dry-run-pure
  push_stash "${repo}" old-a 30
  before="$(git -C "${repo}" rev-parse 'stash@{0}')"
  out="${tmpdir}/dry-run-pure.out"

  run_sut "${out}" "${repo}"
  assert_status 0 "${out}" dry-run-pure
  [[ "$(git -C "${repo}" rev-parse 'stash@{0}')" == "${before}" ]] ||
    fail "dry-run-pure: stash@{0} changed during a dry run"
  assert_archive_count "${repo}" 0 dry-run-pure
  pass
}

test_dry_run_reports_and_preserves
test_apply_archives_then_drops
test_archived_stash_is_recoverable
test_age_threshold_is_parsed_base_ten
test_invalid_duration_is_a_usage_error
test_unreadable_stash_list_fails_loudly
test_unreadable_archive_refs_fail_loudly
test_failed_archive_write_aborts_the_drop
test_sha_mismatch_gate_blocks_the_drop
test_concurrent_push_does_not_block_pruning
test_vanished_stash_is_skipped_not_mistaken
test_second_instance_is_locked_out
test_rejected_entry_does_not_shift_reported_positions
test_sweep_archive_respects_retention
test_sweep_never_deletes_this_runs_archive
test_zero_retention_disables_expiry
test_linked_worktrees_share_one_stash_stack
test_dry_run_writes_nothing_on_a_stale_snapshot

printf '%d passed\n' "${tests_passed}"
