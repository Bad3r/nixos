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
# Shims are written at runtime; /usr/bin/env does not exist in a nix build
# sandbox, so the interpreter is resolved rather than assumed.
SHIM_SHEBANG="#!$(command -v bash)"

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

declare -a tests_ran=()

pass() {
  tests_ran+=("${FUNCNAME[1]}")
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
  # The destructive mode closes with a total too, not just the dry run.
  assert_contains "${out}" 'applied: 1 stash\(es\) archived and dropped, 0 archive ref\(s\) deleted' apply
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

  # The arithmetic downstream is 64-bit and wraps silently: an unbounded digit
  # run can put age_cutoff in the future, selecting every stash including
  # fresh ones. Out of range must take the usage-error path instead.
  run_sut "${out}" "${repo}" --age 999999999999999
  assert_status 64 "${out}" bad-duration-overflow
  assert_contains "${out}" "invalid duration '999999999999999'" bad-duration-overflow

  run_sut "${out}" "${repo}" --archive-retention 999999999999999
  assert_status 64 "${out}" bad-retention-overflow
  # Pinned by message: the no-sweep guard also exits 64, so the status alone
  # cannot show the duration bound is what rejected this.
  assert_contains "${out}" "invalid duration '999999999999999'" bad-retention-overflow

  # The bound is on digits, not magnitude of intent: 6 digits still parse.
  run_sut "${out}" "${repo}" --age 999999
  assert_status 0 "${out}" bad-duration-max
  assert_contains "${out}" 'no stashes older than 999999d' bad-duration-max
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
${SHIM_SHEBANG}
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
${SHIM_SHEBANG}
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

  # A ref store that just rejected a write is where not to start deleting
  # recovery material: the old archive ref is the only copy of a stash an
  # earlier run dropped here.
  "${REAL_GIT}" -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" archive-fail-sweep
  assert_contains "${out}" 'archive sweep skipped' archive-fail-sweep
  assert_not_contains "${out}" 'deleted archive ref' archive-fail-sweep
  assert_archive_count "${repo}" 1 archive-fail-sweep
  pass
}

test_unreadable_live_stack_blocks_the_drop() {
  local out shim
  make_fixture live-unreadable
  push_stash "${repo}" old-a 30
  out="${tmpdir}/live-unreadable.out"

  # Only the --format=%H listing locate_stash_index reads is failed, leaving
  # the snapshot listing intact. This is the branch that distinguishes "stack
  # unreadable" from "commit gone"; collapsing the two would report a vanished
  # stash where the stack simply could not be read.
  shim="${tmpdir}/live-unreadable-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *"--format=%H"* ]]; then
  echo "fatal: forced stash list failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" live-unreadable
  assert_contains "${out}" 'cannot re-read the stash list' live-unreadable
  assert_not_contains "${out}" 'is no longer in the stash stack' live-unreadable
  assert_stash_subject_present "${repo}" old-a live-unreadable
  assert_archive_count "${repo}" 0 live-unreadable

  # Same failure state as an unreadable initial listing, so the sweep must be
  # suppressed too: those archive refs are the only copies of stashes already
  # dropped in this repository.
  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" live-unreadable-sweep
  assert_contains "${out}" 'cannot re-read the stash list' live-unreadable-sweep
  assert_not_contains "${out}" 'deleted archive ref' live-unreadable-sweep
  assert_archive_count "${repo}" 1 live-unreadable-sweep
  pass
}

test_wrong_drop_is_caught_and_rescued() {
  local out shim victim_sha
  make_fixture wrong-drop
  push_stash "${repo}" old-a 30
  push_stash "${repo}" neighbour 1
  out="${tmpdir}/wrong-drop.out"
  victim_sha="$(git -C "${repo}" rev-parse 'stash@{0}')"

  # git has no sha-keyed drop, so a push landing between the gate and the drop
  # shifts stash@{idx} onto a neighbour this run never archived. git names the
  # commit it dropped; the run must notice and make it durable rather than
  # leaving it unreachable until gc.
  shim="${tmpdir}/wrong-drop-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *" stash drop "* ]]; then
  printf 'Dropped stash@{1} (%s)\n' "${victim_sha}"
  exit 0
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" wrong-drop
  assert_contains "${out}" 'shifted before the drop' wrong-drop
  assert_contains "${out}" "archived it as refs/stash-archive" wrong-drop
  assert_not_contains "${out}" 'dropped stash@\{1\} \(recover' wrong-drop
  # The commit git reported dropping is now reachable through a ref.
  "${REAL_GIT}" -C "${repo}" show-ref --verify --quiet \
    "refs/stash-archive/$(date -u +%F)/${victim_sha:0:12}" ||
    fail "wrong-drop: the wrongly dropped commit was not archived"
  pass
}

test_drop_failure_keeps_the_archive_ref() {
  local out shim
  make_fixture drop-fail
  push_stash "${repo}" old-a 30
  out="${tmpdir}/drop-fail.out"

  # The only place asserting the archive ref is kept when the destructive step
  # itself fails, which is what makes a failed drop non-lossy.
  shim="${tmpdir}/drop-fail-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *" stash drop "* ]]; then
  echo "fatal: forced drop failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" drop-fail
  assert_contains "${out}" 'drop failed for stash@\{0\}.*archive ref .* kept' drop-fail
  assert_stash_subject_present "${repo}" old-a drop-fail
  assert_archive_count "${repo}" 1 drop-fail

  # Same rule for a failed drop: this run wrote nothing it could rely on here.
  "${REAL_GIT}" -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" drop-fail-sweep
  assert_contains "${out}" 'archive sweep skipped' drop-fail-sweep
  assert_not_contains "${out}" 'deleted archive ref' drop-fail-sweep
  "${REAL_GIT}" -C "${repo}" show-ref --verify --quiet refs/stash-archive/2020-01-01/aaaaaaaaaaaa ||
    fail "drop-fail-sweep: the stale archive ref was expired after a failed drop"
  pass
}

test_archive_ref_deletion_failure_is_reported() {
  local out shim
  make_fixture sweep-delete-fail
  out="${tmpdir}/sweep-delete-fail.out"
  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD

  shim="${tmpdir}/sweep-delete-fail-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *" update-ref -d "* ]]; then
  echo "fatal: forced update-ref -d failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" sweep-delete-fail
  assert_contains "${out}" 'failed to delete archive ref' sweep-delete-fail
  assert_archive_count "${repo}" 1 sweep-delete-fail
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
${SHIM_SHEBANG}
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

test_wholly_unusable_listing_is_not_reported_as_clean() {
  local out shim
  make_fixture all-rejected
  push_stash "${repo}" old-a 30
  out="${tmpdir}/all-rejected.out"

  # Every entry rejected, so nothing can be classified. Reporting an age result
  # here would assert the one thing the run could not determine, and the sweep
  # message must describe the state accurately.
  shim="${tmpdir}/all-rejected-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* ]]; then
  printf 'stash@{0}||not-a-sha|garbage\n'
  exit 0
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" all-rejected
  assert_contains "${out}" 'no stash older than 14d was selected, and the listing had entries' all-rejected
  assert_not_contains "${out}" 'no stashes older than' all-rejected
  # The listing was read here, so the skip message must not claim otherwise.
  assert_contains "${out}" 'could not be read or interpreted' all-rejected
  assert_not_contains "${out}" 'deleted archive ref' all-rejected
  git -C "${repo}" show-ref --verify --quiet refs/stash-archive/2020-01-01/aaaaaaaaaaaa ||
    fail "all-rejected: the archive ref was expired despite an unusable listing"
  pass
}

test_leading_zero_committer_date_is_read_as_decimal() {
  local out shim
  make_fixture octal-ct
  push_stash "${repo}" not-old 1
  out="${tmpdir}/octal-ct.out"

  # The shape check accepts a leading zero and bash arithmetic reads it as
  # octal: 07000000000 compares as 939524096, old enough to drop, while its
  # decimal value is a date in 2191 that must be kept.
  shim="${tmpdir}/octal-ct-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* ]]; then
  "${REAL_GIT}" "\$@" | awk -F'|' -v OFS='|' '{ \$2 = "07000000000"; print }'
  exit \${PIPESTATUS[0]}
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" octal-ct
  assert_contains "${out}" 'no stashes older than 14d' octal-ct
  assert_not_contains "${out}" 'dropped stash@' octal-ct
  assert_stash_subject_present "${repo}" not-old octal-ct
  assert_archive_count "${repo}" 0 octal-ct
  pass
}

test_out_of_range_committer_date_is_rejected() {
  local out shim
  make_fixture huge-ct
  push_stash "${repo}" fresh 1
  out="${tmpdir}/huge-ct.out"

  # ct feeds the same 64-bit arithmetic --age is bounded for. A value past
  # INTMAX_MAX wraps negative and satisfies `ct <= age_cutoff` regardless of
  # the threshold, selecting a stash pushed today for dropping.
  shim="${tmpdir}/huge-ct-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* ]]; then
  "${REAL_GIT}" "\$@" | awk -F'|' -v OFS='|' '{ \$2 = "9999999999999999999"; print }'
  exit \${PIPESTATUS[0]}
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" huge-ct
  assert_contains "${out}" 'unparsable stash list entry' huge-ct
  assert_not_contains "${out}" 'dropped stash@' huge-ct
  assert_stash_subject_present "${repo}" fresh huge-ct
  pass
}

test_blank_line_in_the_live_stack_does_not_shift_lookup() {
  local out shim
  make_fixture blank-live
  push_stash "${repo}" old-a 30
  push_stash "${repo}" fresh 1
  out="${tmpdir}/blank-live.out"

  # Only the sha listing that locate_stash_index reads is shimmed, and only its
  # first line. A blank line occupies slot 0, so old-a is still at slot 1;
  # stepping over it would resolve old-a to slot 0 and the sha gate would then
  # reject a drop that is perfectly valid.
  shim="${tmpdir}/blank-live-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *"--format=%H"* ]]; then
  printf '\n'
  "${REAL_GIT}" "\$@" | tail -n +2
  exit \${PIPESTATUS[0]}
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" blank-live
  assert_contains "${out}" 'dropped stash@\{1\}' blank-live
  assert_not_contains "${out}" 'no longer resolves to' blank-live
  assert_stash_subject_present "${repo}" fresh blank-live
  assert_stash_subject_absent "${repo}" old-a blank-live
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
${SHIM_SHEBANG}
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
${SHIM_SHEBANG}
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
  lock="${XDG_RUNTIME_DIR}/prune-old-stashes.$(id -u)/lock"
  mkdir -p "$(dirname "${lock}")"

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

test_hostile_lock_dir_is_refused_not_followed() {
  local out victim base
  make_fixture lock-dir
  push_stash "${repo}" old-a 30
  out="${tmpdir}/lock-dir.out"

  # The attack the private lock directory exists to stop: another user creates
  # the predictable name first, pointing it somewhere this uid can write. The
  # run must refuse rather than open a leaf under it.
  base="${tmpdir}/hostile-base"
  victim="${tmpdir}/hostile-target"
  mkdir -p "${base}" "${victim}"
  ln -s "${victim}" "${base}/prune-old-stashes.$(id -u)"

  TMPDIR="${base}" XDG_RUNTIME_DIR="${base}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" lock-dir
  assert_contains "${out}" 'lock directory is not a directory this user owns' lock-dir
  assert_not_contains "${out}" 'another instance is already running' lock-dir

  # Refused before the lock was opened, so nothing was written through the
  # symlink and no repository was touched.
  [[ ! -e ${victim}/lock ]] || fail "lock-dir: the run opened a lock through the symlink"
  assert_stash_count "${repo}" 1 lock-dir
  assert_archive_count "${repo}" 0 lock-dir
  pass
}

test_lock_leaf_is_not_a_predictable_name_in_the_base() {
  local out victim base
  make_fixture lock-leaf
  push_stash "${repo}" old-a 30
  out="${tmpdir}/lock-leaf.out"

  # The regression this replaced: a symlink at the old leaf name was followed
  # by `exec 200>` and truncated. That name is no longer opened at all, so a
  # file planted there survives a full run.
  base="${tmpdir}/leaf-base"
  victim="${tmpdir}/leaf-target"
  mkdir -p "${base}"
  printf 'important\n' >"${victim}"
  ln -s "${victim}" "${base}/prune-old-stashes.$(id -u).lock"

  TMPDIR="${base}" XDG_RUNTIME_DIR="${base}" run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" lock-leaf
  [[ -s ${victim} ]] || fail "lock-leaf: the old leaf name was still opened and truncated" "${out}"
  assert_stash_count "${repo}" 0 lock-leaf
  pass
}

test_planted_lock_leaf_is_refused_not_followed() {
  local out victim base dir
  make_fixture lock-planted
  push_stash "${repo}" old-a 30
  out="${tmpdir}/lock-planted.out"

  # A run interrupted before the chmod leaves the directory writable under a
  # loose umask, so the leaf can be planted afterwards and outlives the chmod.
  # The directory checks inspect the directory, not what is in it.
  base="${tmpdir}/planted-base"
  victim="${tmpdir}/planted-target"
  dir="${base}/prune-old-stashes.$(id -u)"
  mkdir -p "${dir}"
  chmod 777 "${dir}"
  printf 'important\n' >"${victim}"
  ln -s "${victim}" "${dir}/lock"

  TMPDIR="${base}" XDG_RUNTIME_DIR="${base}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" lock-planted
  assert_contains "${out}" 'lock path is a symlink, refusing to open it' lock-planted
  [[ -s ${victim} ]] || fail "lock-planted: the run followed the planted leaf and truncated it" "${out}"
  assert_stash_count "${repo}" 1 lock-planted
  assert_archive_count "${repo}" 0 lock-planted
  pass
}

test_lock_dir_is_created_private_not_chmodded_later() {
  local out base dir shim mode prev_umask
  make_fixture lock-umask
  out="${tmpdir}/lock-umask.out"

  base="${tmpdir}/umask-base"
  dir="${base}/prune-old-stashes.$(id -u)"
  mkdir -p "${base}"

  # A no-op chmod leaves the directory exactly as mkdir made it, which is the
  # state a run interrupted before the chmod leaves behind. Asserting the mode
  # after a real chmod would read 700 whichever way it was created, so it would
  # pass with the private umask removed.
  shim="${tmpdir}/umask-bin"
  mkdir -p "${shim}"
  printf '%s\nexit 0\n' "${SHIM_SHEBANG}" >"${shim}/chmod"
  chmod +x "${shim}/chmod"

  # Not a subshell: run_sut sets sut_status, which would not survive one.
  prev_umask="$(umask)"
  umask 000
  PATH="${shim}:${PATH}" TMPDIR="${base}" XDG_RUNTIME_DIR="${base}" \
    run_sut "${out}" "${repo}"
  umask "${prev_umask}"

  assert_status 0 "${out}" lock-umask
  mode="$(stat -c '%a' "${dir}")"
  [[ ${mode} == 700 ]] || fail "lock-umask: lock directory created with mode ${mode}, expected 700 before any chmod" "${out}"
  pass
}

test_missing_flock_is_reported_as_itself() {
  local out shim tool tool_path
  make_fixture no-flock
  push_stash "${repo}" old-a 30
  out="${tmpdir}/no-flock.out"

  # An exclusive PATH rather than a prepended shim: absence is what is under
  # test, so flock has to be unreachable, not shadowed. Folding the guard back
  # into the `flock -n` `||` branch turns the message into contention with a
  # process that never exits, which the negative assertion below catches.
  shim="${tmpdir}/no-flock-bin"
  mkdir -p "${shim}"
  for tool in bash sh env git date id cat mkdir; do
    tool_path="$(command -v "${tool}")" || continue
    ln -s "${tool_path}" "${shim}/${tool}"
  done
  [[ ! -e ${shim}/flock ]] || fail "no-flock: the shim resolved a flock it must not have"

  PATH="${shim}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" no-flock
  assert_contains "${out}" 'flock is required to serialize runs' no-flock
  assert_not_contains "${out}" 'another instance is already running' no-flock

  # The guard runs before any repository is read, so nothing was touched.
  assert_stash_count "${repo}" 1 no-flock
  assert_archive_count "${repo}" 0 no-flock

  # From outside a repository the missing tool must still be what is reported.
  # With the guard placed after repository resolution this is exit 64 for "not
  # inside a git repository", which names neither the cause nor the fix.
  local outside
  outside="${tmpdir}/no-flock-outside"
  mkdir -p "${outside}"
  PATH="${shim}" run_sut "${out}" "${outside}" --apply
  assert_status 1 "${out}" no-flock-outside
  assert_contains "${out}" 'flock is required to serialize runs' no-flock-outside
  assert_not_contains "${out}" 'not inside a git repository' no-flock-outside
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

test_retention_grants_a_full_window() {
  local out yesterday
  make_fixture retention-window
  out="${tmpdir}/retention-window.out"

  # Archive refs carry a date, so epoch is midnight of that date while the
  # cutoff is an instant. A ref written yesterday must survive a 1-day window
  # no matter what time of day the sweep runs.
  yesterday="$(date -u -d '1 day ago' +%F)"
  git -C "${repo}" update-ref "refs/stash-archive/${yesterday}/aaaaaaaaaaaa" HEAD

  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 1 --apply
  assert_status 0 "${out}" retention-window
  assert_not_contains "${out}" 'deleted archive ref' retention-window
  assert_archive_count "${repo}" 1 retention-window

  # Two days back is outside a 1-day window and still expires.
  git -C "${repo}" update-ref "refs/stash-archive/$(date -u -d '3 days ago' +%F)/bbbbbbbbbbbb" HEAD
  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 1 --apply
  assert_status 0 "${out}" retention-window-expires
  assert_contains "${out}" 'deleted archive ref' retention-window-expires
  assert_archive_count "${repo}" 1 retention-window-expires
  pass
}

test_non_date_archive_ref_is_not_swept() {
  local out
  make_fixture non-date-ref
  out="${tmpdir}/non-date-ref.out"

  # `date -u -d` resolves both of these to real timestamps, so without a shape
  # check they would drive an update-ref -d.
  git -C "${repo}" update-ref 'refs/stash-archive/@0/aaaaaaaaaaaa' HEAD
  git -C "${repo}" update-ref 'refs/stash-archive/yesterday/bbbbbbbbbbbb' HEAD

  run_sut "${out}" "${repo}" --sweep-archive --apply
  assert_status 0 "${out}" non-date-ref
  assert_contains "${out}" 'skipping archive ref with a non-date component' non-date-ref
  assert_not_contains "${out}" 'deleted archive ref' non-date-ref
  assert_archive_count "${repo}" 2 non-date-ref
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
  # A sweep the operator asked for must not be a silent no-op.
  assert_contains "${out}" 'archive retention disabled' zero-retention-dry
  assert_contains "${out}" 'dry-run: nothing selected' zero-retention-dry

  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 0 --apply
  assert_status 0 "${out}" zero-retention-apply
  assert_not_contains "${out}" 'deleted archive ref' zero-retention-apply
  assert_contains "${out}" 'archive retention disabled' zero-retention-apply
  assert_archive_count "${repo}" 2 zero-retention-apply

  # A window of 1 still expires them, so the guard is not disabling the sweep.
  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 1 --apply
  assert_status 0 "${out}" zero-retention-contrast
  assert_archive_count "${repo}" 0 zero-retention-contrast
  pass
}

test_blank_listing_line_is_rejected_not_skipped() {
  local out shim
  make_fixture blank-line
  push_stash "${repo}" old-a 30
  push_stash "${repo}" old-b 30
  out="${tmpdir}/blank-line.out"

  # A blank line occupies a stack slot like any other entry. Skipped silently
  # it would shift every position below it, the defect the shape check guards
  # against for garbage lines.
  shim="${tmpdir}/blank-line-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *"--format=%gd|%ct|%H|%s"* ]]; then
  printf '\n'
  "${REAL_GIT}" "\$@" | tail -n +2
  exit \${PIPESTATUS[0]}
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}"
  assert_status 1 "${out}" blank-line
  assert_contains "${out}" 'ERROR: unparsable stash list entry' blank-line
  assert_contains "${out}" 'would archive stash@\{1\}' blank-line
  assert_not_contains "${out}" 'would archive stash@\{0\}' blank-line
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
${SHIM_SHEBANG}
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

  # A listing this run could not fully interpret is the same failure state as
  # one it could not read, so the sweep must be suppressed for it too.
  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" bad-entry-sweep
  assert_contains "${out}" 'ERROR: unparsable stash list entry' bad-entry-sweep
  assert_not_contains "${out}" 'deleted archive ref' bad-entry-sweep
  git -C "${repo}" show-ref --verify --quiet refs/stash-archive/2020-01-01/aaaaaaaaaaaa ||
    fail "bad-entry-sweep: the stale archive ref was expired despite a garbled listing"
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

test_all_worktrees_processes_independent_repos() {
  local out other trees
  trees="${tmpdir}/scan-root-a"
  mkdir -p "${trees}"
  make_fixture standalone
  other="${trees}/independent"
  git init -q -b main "${other}"
  init_repo_config "${other}"
  printf '%s\n' base >"${other}/f"
  git -C "${other}" add f
  git -C "${other}" commit -q -m "initial commit"
  push_stash "${other}" old-a 30
  out="${tmpdir}/all-worktrees.out"

  # The run starts outside the scanned root, so the enumeration is the only
  # path by which the second repository can be reached.
  run_sut "${out}" "${repo}" --all-worktrees --root "${trees}"
  assert_status 0 "${out}" all-worktrees
  assert_contains "${out}" "repo: ${repo}$" all-worktrees
  assert_contains "${out}" "repo: ${other}$" all-worktrees
  assert_contains "${out}" 'would archive stash@\{0\}' all-worktrees

  # A --root that would never be scanned is a typo, not a preference.
  run_sut "${out}" "${repo}" --root "${trees}"
  assert_status 64 "${out}" all-worktrees-off
  assert_contains "${out}" 'has no effect without --all-worktrees' all-worktrees-off
  assert_not_contains "${out}" "repo: ${other}$" all-worktrees-off
  pass
}

test_root_is_repeatable_and_defaults_to_home_trees() {
  local out second third
  make_fixture multi-root
  second="${tmpdir}/scan-root-b/repo-b"
  third="${HOME}/trees/nixos/repo-c"
  local dir
  for dir in "${second}" "${third}"; do
    mkdir -p "$(dirname "${dir}")"
    git init -q -b main "${dir}"
    init_repo_config "${dir}"
    printf '%s\n' base >"${dir}/f"
    git -C "${dir}" add f
    git -C "${dir}" commit -q -m "initial commit"
    push_stash "${dir}" old-a 30
  done
  out="${tmpdir}/multi-root.out"

  # Every --root is scanned, not just the last one.
  run_sut "${out}" "${repo}" --all-worktrees --root "${tmpdir}/scan-root-b" --root "${HOME}/trees/nixos"
  assert_status 0 "${out}" multi-root
  assert_contains "${out}" "repo: ${second}$" multi-root
  assert_contains "${out}" "repo: ${third}$" multi-root

  # With no --root the default is $HOME/trees/nixos.
  run_sut "${out}" "${repo}" --all-worktrees
  assert_status 0 "${out}" multi-root-default
  assert_contains "${out}" "repo: ${third}$" multi-root-default
  assert_not_contains "${out}" "repo: ${second}$" multi-root-default

  # The --root=DIR form reaches the same handling as the two-word form.
  run_sut "${out}" "${repo}" --all-worktrees "--root=${tmpdir}/scan-root-b"
  assert_status 0 "${out}" multi-root-equals
  assert_contains "${out}" "repo: ${second}$" multi-root-equals
  assert_not_contains "${out}" "repo: ${third}$" multi-root-equals

  # So do --age=DUR and --archive-retention=DUR.
  run_sut "${out}" "${repo}" --age=3months
  assert_status 64 "${out}" multi-root-age-equals
  assert_contains "${out}" "invalid duration '3months'" multi-root-age-equals

  run_sut "${out}" "${repo}" --archive-retention=999999999999999
  assert_status 64 "${out}" multi-root-retention-equals
  # Three paths reach exit 64 here: the duration bound, the no-sweep guard, and
  # the unknown-argument fallthrough a missing --archive-retention=* arm would
  # take. Only the message distinguishes them.
  assert_contains "${out}" "invalid duration '999999999999999'" multi-root-retention-equals

  run_sut "${out}" "${repo}" --age=010
  assert_status 0 "${out}" multi-root-age-equals-ok
  assert_contains "${out}" 'no stashes older than 10d' multi-root-age-equals-ok

  run_sut "${out}" "${repo}" --root
  assert_status 64 "${out}" multi-root-usage
  assert_contains "${out}" 'requires a value' multi-root-usage

  # Same rule for a retention window that would never be applied: it is read
  # only inside the sweep, so without --sweep-archive the operator's value is
  # the one thing the run definitely did not honour.
  run_sut "${out}" "${repo}" --apply --archive-retention 7
  assert_status 64 "${out}" retention-without-sweep
  assert_contains "${out}" 'has no effect without --sweep-archive' retention-without-sweep

  run_sut "${out}" "${repo}" --sweep-archive --archive-retention 7
  assert_status 0 "${out}" retention-with-sweep

  # The default is not "explicit", so an ordinary run is unaffected.
  run_sut "${out}" "${repo}"
  assert_status 0 "${out}" retention-default
  pass
}

test_invalid_git_dir_does_not_resolve_upward() {
  local out enclosing
  make_fixture fake-git
  out="${tmpdir}/fake-git.out"

  # An enclosing repository with a stash, holding the scanned root. Kept out of
  # $HOME so this case does not depend on what other cases did to it.
  enclosing="${tmpdir}/fake-git-enclosing"
  git init -q -b main "${enclosing}"
  init_repo_config "${enclosing}"
  printf '%s\n' base >"${enclosing}/f"
  git -C "${enclosing}" add f
  git -C "${enclosing}" commit -q -m "initial commit"
  push_stash "${enclosing}" precious-enclosing 30

  # An empty .git *directory* passes an -e check but does not validate, so git
  # discovery skips it and walks up. rev-parse --show-toplevel then succeeds
  # and names the enclosing repository.
  mkdir -p "${enclosing}/trees/fake/.git"

  run_sut "${out}" "${repo}" --all-worktrees --root "${enclosing}/trees"
  assert_status 1 "${out}" fake-git
  assert_contains "${out}" 'not a checkout root, skipping' fake-git
  assert_not_contains "${out}" "repo: ${enclosing}$" fake-git
  assert_not_contains "${out}" 'precious-enclosing' fake-git
  assert_stash_count "${enclosing}" 1 fake-git
  pass
}

test_unverifiable_checkout_root_is_skipped() {
  local out shim enclosing
  make_fixture prefix-fail
  out="${tmpdir}/prefix-fail.out"

  enclosing="${tmpdir}/prefix-fail-enclosing"
  git init -q -b main "${enclosing}"
  init_repo_config "${enclosing}"
  printf '%s\n' base >"${enclosing}/f"
  git -C "${enclosing}" add f
  git -C "${enclosing}" commit -q -m "initial commit"
  push_stash "${enclosing}" precious-enclosing 30
  git init -q -b main "${enclosing}/trees/inner"
  init_repo_config "${enclosing}/trees/inner"

  # The guard must fail closed: a --show-prefix that cannot be run is not
  # evidence that the directory is a repository root, and treating it as such
  # registers whatever --show-toplevel resolved, here the enclosing repository.
  shim="${tmpdir}/prefix-fail-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *" --show-prefix "* ]]; then
  echo "fatal: forced show-prefix failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply --all-worktrees --root "${enclosing}/trees"
  assert_status 1 "${out}" prefix-fail
  assert_contains "${out}" 'not a checkout root, skipping' prefix-fail
  assert_not_contains "${out}" "repo: ${enclosing}$" prefix-fail
  assert_not_contains "${out}" 'precious-enclosing' prefix-fail
  assert_stash_count "${enclosing}" 1 prefix-fail
  pass
}

test_broken_checkout_under_a_root_is_reported() {
  local out scan good
  make_fixture broken-checkout
  scan="${tmpdir}/broken-scan"
  mkdir -p "${scan}"
  out="${tmpdir}/broken-checkout.out"

  # A healthy sibling, so the run is not empty and the failure cannot hide
  # behind the "no checkouts" message.
  good="${scan}/good"
  git init -q -b main "${good}"
  init_repo_config "${good}"
  printf '%s\n' base >"${good}/f"
  git -C "${good}" add f
  git -C "${good}" commit -q -m "initial commit"
  push_stash "${good}" old-a 30

  # A .git pointing at a gitdir that no longer exists.
  mkdir -p "${scan}/broken"
  printf 'gitdir: %s\n' "${tmpdir}/no-such-gitdir" >"${scan}/broken/.git"

  run_sut "${out}" "${repo}" --all-worktrees --root "${scan}"
  assert_status 1 "${out}" broken-checkout
  assert_contains "${out}" 'broken checkout, skipping' broken-checkout
  assert_not_contains "${out}" 'no checkouts directly under root' broken-checkout
  # The healthy sibling is still processed.
  assert_contains "${out}" "repo: ${good}$" broken-checkout

  # With no healthy sibling the root still contains a checkout, just an
  # unreadable one, so calling it an absence would misdescribe it and count
  # the same problem twice.
  rm -rf "${good}"
  run_sut "${out}" "${repo}" --all-worktrees --root "${scan}"
  assert_status 1 "${out}" broken-only
  assert_contains "${out}" 'broken checkout, skipping' broken-only
  assert_not_contains "${out}" 'no checkouts directly under root' broken-only
  assert_contains "${out}" '1 failure\(s\)' broken-only

  # Corruption is counted under the default root too, unlike a missing or
  # empty root, which the default is exempt from.
  rm -rf "${HOME}/trees"
  mkdir -p "${HOME}/trees/nixos/broken"
  printf 'gitdir: %s\n' "${tmpdir}/no-such-gitdir" >"${HOME}/trees/nixos/broken/.git"
  run_sut "${out}" "${repo}" --all-worktrees
  assert_status 1 "${out}" broken-default-root
  assert_contains "${out}" 'broken checkout, skipping' broken-default-root
  pass
}

test_corruption_is_not_reported_as_a_usage_error() {
  local out scan outside
  make_fixture usage-vs-failure
  scan="${tmpdir}/all-broken-scan"
  mkdir -p "${scan}/broken"
  printf 'gitdir: %s\n' "${tmpdir}/no-such-gitdir" >"${scan}/broken/.git"
  outside="${tmpdir}/not-a-repo"
  mkdir -p "${outside}"
  out="${tmpdir}/usage-vs-failure.out"

  # Run from outside any repository, so `roots` ends up empty and the
  # no-repositories branch is reached with failures already counted. Exiting 64
  # there would report corruption inside the tree as a bad invocation and
  # discard the failure count.
  run_sut "${out}" "${outside}" --all-worktrees --root "${scan}"
  assert_status 1 "${out}" usage-vs-failure
  assert_contains "${out}" 'broken checkout, skipping' usage-vs-failure
  assert_contains "${out}" '1 failure\(s\)' usage-vs-failure

  # With nothing counted, the same branch is a usage error. Reached through the
  # default root, which is exempt from the failure count: a named root would
  # increment it and take the branch above, pinning nothing new.
  rm -rf "${HOME}/trees"
  run_sut "${out}" "${outside}" --all-worktrees
  assert_status 64 "${out}" usage-vs-failure-empty
  assert_contains "${out}" 'no repositories found under the scanned roots' usage-vs-failure-empty
  assert_not_contains "${out}" 'failure\(s\)' usage-vs-failure-empty

  # A named empty root does count, so it stays on the failure side.
  rm -rf "${scan}"
  mkdir -p "${scan}"
  run_sut "${out}" "${outside}" --all-worktrees --root "${scan}"
  assert_status 1 "${out}" usage-vs-failure-named
  assert_contains "${out}" 'no checkouts directly under root' usage-vs-failure-named
  pass
}

test_root_without_checkouts_is_reported() {
  local out empty_root
  make_fixture rootless
  empty_root="${tmpdir}/root-one-level-too-high"
  mkdir -p "${empty_root}/container/deeper"
  out="${tmpdir}/rootless.out"

  # The root exists and matches directories, but only one level is scanned, so
  # nothing registers. Silent, that is a clean report over an unscanned tree.
  run_sut "${out}" "${repo}" --all-worktrees --root "${empty_root}"
  assert_status 1 "${out}" rootless
  assert_contains "${out}" 'no checkouts directly under root' rootless

  # The default root is exempt: a host may simply have no worktrees yet.
  rm -rf "${HOME}/trees"
  mkdir -p "${HOME}/trees/nixos"
  run_sut "${out}" "${repo}" --all-worktrees
  assert_status 0 "${out}" rootless-default
  assert_contains "${out}" 'no checkouts directly under root' rootless-default
  pass
}

test_non_checkout_under_a_root_is_not_resolved_upward() {
  local out enclosing
  make_fixture outsider
  out="${tmpdir}/enclosing.out"

  # $HOME is itself a repository with a stash, the dotfiles case. A plain
  # directory under the scanned root would make `rev-parse --show-toplevel`
  # walk up to it and pull it into the scan set.
  enclosing="${HOME}"
  git init -q -b main "${enclosing}"
  init_repo_config "${enclosing}"
  printf '%s\n' dot >"${enclosing}/f"
  git -C "${enclosing}" add f
  git -C "${enclosing}" commit -q -m "initial commit"
  push_stash "${enclosing}" precious-dotfiles 30
  mkdir -p "${enclosing}/trees/nixos/notes"

  run_sut "${out}" "${repo}" --all-worktrees
  assert_status 0 "${out}" enclosing
  assert_not_contains "${out}" "repo: ${enclosing}$" enclosing
  assert_not_contains "${out}" 'precious-dotfiles' enclosing
  assert_stash_count "${enclosing}" 1 enclosing
  pass
}

test_unusable_root_is_reported_not_expanded() {
  local out
  make_fixture bad-root
  out="${tmpdir}/bad-root.out"

  # An empty value makes `"$scan_root"/*/` expand to `/*/`, enumerating every
  # top-level directory of the filesystem root and running git in each.
  run_sut "${out}" "${repo}" --all-worktrees --root ""
  assert_status 1 "${out}" bad-root-empty
  assert_contains "${out}" 'root does not exist, skipping' bad-root-empty
  [[ $(grep -c '^repo: ' "${out}") -eq 1 ]] ||
    fail "bad-root-empty: an empty root expanded into a scan set" "${out}"

  # A mistyped root matched nothing and reported a clean run over a tree that
  # was never scanned.
  run_sut "${out}" "${repo}" --all-worktrees --root "${tmpdir}/no-such-tree"
  assert_status 1 "${out}" bad-root-missing
  assert_contains "${out}" 'root does not exist, skipping' bad-root-missing

  # The default root is allowed to be absent: a host may have no worktrees.
  rm -rf "${HOME}/trees"
  run_sut "${out}" "${repo}" --all-worktrees
  assert_status 0 "${out}" bad-root-default
  pass
}

test_unreadable_repo_is_not_swept() {
  local out
  make_fixture unreadable-sweep
  push_stash "${repo}" old-a 30
  out="${tmpdir}/unreadable-sweep.out"

  # Archive refs are the only copies of stashes already dropped here, so a
  # repository this run could not read must not have them expired.
  git -C "${repo}" update-ref refs/stash-archive/2020-01-01/aaaaaaaaaaaa HEAD
  printf '%s\n' deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >"${repo}/.git/refs/stash"

  run_sut "${out}" "${repo}" --apply --sweep-archive
  assert_status 1 "${out}" unreadable-sweep
  assert_contains "${out}" 'ERROR: cannot read the stash list' unreadable-sweep
  assert_not_contains "${out}" 'deleted archive ref' unreadable-sweep
  assert_archive_count "${repo}" 1 unreadable-sweep
  pass
}

test_unresolvable_common_dir_is_reported() {
  local out shim
  make_fixture common-dir-fail
  push_stash "${repo}" old-a 30
  out="${tmpdir}/common-dir-fail.out"

  shim="${tmpdir}/common-dir-fail-bin"
  mkdir -p "${shim}"
  cat >"${shim}/git" <<SHIM
${SHIM_SHEBANG}
if [[ " \$* " == *" --git-common-dir "* ]]; then
  echo "fatal: forced rev-parse failure" >&2
  exit 1
fi
exec "${REAL_GIT}" "\$@"
SHIM
  chmod +x "${shim}/git"

  PATH="${shim}:${PATH}" run_sut "${out}" "${repo}" --apply
  assert_status 1 "${out}" common-dir-fail
  assert_contains "${out}" 'cannot resolve the common git dir' common-dir-fail
  assert_stash_subject_present "${repo}" old-a common-dir-fail
  assert_archive_count "${repo}" 0 common-dir-fail
  pass
}

test_cdpath_does_not_divert_the_dedup_key() {
  local out decoy scan other
  make_fixture cdpath-a
  push_stash "${repo}" old-a 30
  scan="${tmpdir}/cdpath-roots"
  other="${scan}/cdpath-b"
  mkdir -p "${scan}"
  git init -q -b main "${other}"
  init_repo_config "${other}"
  printf '%s\n' base >"${other}/f"
  git -C "${other}" add f
  git -C "${other}" commit -q -m "initial commit"
  push_stash "${other}" old-b 30

  # --git-common-dir returns a bare relative `.git` for a main worktree, and cd
  # consults CDPATH for a target that does not start with / ./ or ../. On a hit
  # it lands in the decoy and echoes the path, so both repositories resolve to
  # one dedup key and the second is silently dropped from the scan set.
  decoy="${tmpdir}/cdpath-decoy"
  mkdir -p "${decoy}/.git"
  out="${tmpdir}/cdpath.out"

  CDPATH="${decoy}" run_sut "${out}" "${repo}" --all-worktrees --root "${scan}"
  assert_status 0 "${out}" cdpath
  assert_contains "${out}" "repo: ${repo}$" cdpath
  assert_contains "${out}" "repo: ${other}$" cdpath
  [[ $(grep -c '^repo: ' "${out}") -eq 2 ]] ||
    fail "cdpath: the dedup key collapsed two unrelated repositories" "${out}"
  pass
}

test_exported_git_dir_does_not_redirect_the_run() {
  local out victim
  make_fixture git-dir-target
  victim="${tmpdir}/git-dir-victim"
  git init -q -b main "${victim}"
  init_repo_config "${victim}"
  printf '%s\n' base >"${victim}/f"
  git -C "${victim}" add f
  git -C "${victim}" commit -q -m "initial commit"
  push_stash "${victim}" victim-stash 30
  out="${tmpdir}/git-dir.out"

  # `git -C <dir>` does not override GIT_DIR/GIT_WORK_TREE, so every git call
  # would resolve to the victim while the report names the repository the
  # operator is actually in.
  GIT_DIR="${victim}/.git" GIT_WORK_TREE="${victim}" \
    run_sut "${out}" "${repo}" --apply
  assert_status 0 "${out}" git-dir
  assert_not_contains "${out}" 'victim-stash' git-dir
  assert_not_contains "${out}" "repo: ${victim}$" git-dir
  assert_stash_count "${victim}" 1 git-dir
  assert_archive_count "${victim}" 0 git-dir
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
test_drop_failure_keeps_the_archive_ref
test_wrong_drop_is_caught_and_rescued
test_archive_ref_deletion_failure_is_reported
test_unreadable_live_stack_blocks_the_drop
test_concurrent_push_does_not_block_pruning
test_vanished_stash_is_skipped_not_mistaken
test_second_instance_is_locked_out
test_missing_flock_is_reported_as_itself
test_hostile_lock_dir_is_refused_not_followed
test_lock_leaf_is_not_a_predictable_name_in_the_base
test_planted_lock_leaf_is_refused_not_followed
test_lock_dir_is_created_private_not_chmodded_later
test_rejected_entry_does_not_shift_reported_positions
test_blank_listing_line_is_rejected_not_skipped
test_blank_line_in_the_live_stack_does_not_shift_lookup
test_wholly_unusable_listing_is_not_reported_as_clean
test_out_of_range_committer_date_is_rejected
test_leading_zero_committer_date_is_read_as_decimal
test_sweep_archive_respects_retention
test_sweep_never_deletes_this_runs_archive
test_zero_retention_disables_expiry
test_retention_grants_a_full_window
test_non_date_archive_ref_is_not_swept
test_linked_worktrees_share_one_stash_stack
test_all_worktrees_processes_independent_repos
test_root_is_repeatable_and_defaults_to_home_trees
test_unusable_root_is_reported_not_expanded
test_non_checkout_under_a_root_is_not_resolved_upward
test_root_without_checkouts_is_reported
test_corruption_is_not_reported_as_a_usage_error
test_broken_checkout_under_a_root_is_reported
test_unverifiable_checkout_root_is_skipped
test_invalid_git_dir_does_not_resolve_upward
test_unreadable_repo_is_not_swept
test_dry_run_writes_nothing_on_a_stale_snapshot
test_exported_git_dir_does_not_redirect_the_run
test_unresolvable_common_dir_is_reported
test_cdpath_does_not_divert_the_dedup_key

# A test function defined but never added to the call list above would leave
# the suite green while guarding nothing, which is the same failure as a test
# that can no longer fail. Compared as sets, not counts: one function listed
# twice and another omitted keeps the totals equal.
expected="$(compgen -A function 'test_' | sort)"
ran="$(printf '%s\n' "${tests_ran[@]}" | sort -u)"
if [[ ${ran} != "${expected}" ]]; then
  printf 'run.sh: defined but never ran:\n%s\n' \
    "$(comm -23 <(printf '%s\n' "${expected}") <(printf '%s\n' "${ran}"))" >&2
  exit 1
fi

printf '%d passed\n' "${#tests_ran[@]}"
