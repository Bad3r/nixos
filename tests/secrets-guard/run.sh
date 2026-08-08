#!/usr/bin/env bash
# shellcheck shell=bash
# Covers scripts/lib/secrets-guard.sh, which decides whether a path: reference
# is allowed to copy the tree into the world-readable store. Every branch here
# is one the guard fails closed on, so a regression that reopens one is a silent
# disclosure rather than a visible break: the whole control is a scan whose
# passing output looks the same as a scan that never ran.
#
# The subject is sourced rather than executed. It has no shebang and defines
# functions for two callers to share, so the suite calls them in-process and
# reaches the three internal helpers as well as secrets_guard_enforce.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/lib/secrets-guard.sh"

if [[ ! -f ${SUT} ]]; then
  printf 'run.sh: SUT not found at %s\n' "${SUT}" >&2
  exit 2
fi
# shellcheck source-path=SCRIPTDIR source=../../scripts/lib/secrets-guard.sh disable=SC1091
source "${SUT}"

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
    printf '%s\n' '--- guard output ---' >&2
    cat "$2" >&2
    printf '%s\n' '--------------------' >&2
  fi
  exit 1
}

init_repo() {
  local repo="$1"

  mkdir -p "${repo}"
  git init -q -b main "${repo}"
  git -C "${repo}" config user.email tests@example.invalid
  git -C "${repo}" config user.name "secrets-guard tests"
}

# The block as modules/development/gitignore.nix emits it, comments included:
# the parser skips comment lines and stops at the first blank one, and the two
# secrets/ entries are what it reduces to decrypted_* and *.dec.*. Written out
# rather than read from the repo's own .gitignore so a mutation test can change
# one line without the fixture depending on the tree the suite runs in.
write_secrets_block() {
  local repo="$1"

  cat >"${repo}/.gitignore" <<'BLOCK'
# Secrets safety (defense-in-depth)
# Do not commit private keys or local env files
########################################
*.agekey
*.key
*.pem
*.p12
*.pfx
.env
.env.*
# Common SSH/private key patterns (allow public keys)
id_*
!id_*.pub
secrets/**/decrypted_*
secrets/**/*.dec.*

# Build output
result
BLOCK
}

# A repo carrying the block, committed, with nothing untracked.
make_repo() {
  local repo="${tmpdir}/$1"

  init_repo "${repo}"
  write_secrets_block "${repo}"
  printf '%s\n' readme >"${repo}/README.md"
  git -C "${repo}" add .gitignore README.md
  git -C "${repo}" commit -q -m "initial commit"
  printf '%s\n' "${repo}"
}

# secrets_guard_paths writes NUL-delimited hits to stdout and returns nonzero
# when it could not scan, so both go through files: command substitution strips
# NUL, which is the ambiguity the guard's own -z handling exists to remove.
scan() {
  local dir="$1"
  scan_rc=0
  secrets_guard_paths "${dir}" >"${tmpdir}/hits.bin" 2>"${tmpdir}/scan.err" || scan_rc=$?
  hits=()
  if [[ -s ${tmpdir}/hits.bin ]]; then
    mapfile -d '' -t hits <"${tmpdir}/hits.bin"
  fi
}

enforce() {
  local dir="$1"
  local copier="${2:-path:${dir}}"
  enforce_rc=0
  secrets_guard_enforce "${dir}" "${copier}" \
    >"${tmpdir}/enforce.out" 2>"${tmpdir}/enforce.err" || enforce_rc=$?
}

has_hit() {
  local want="$1"
  local hit
  for hit in "${hits[@]}"; do
    [[ ${hit} == "${want}" ]] && return 0
  done
  return 1
}

assert_hit() {
  local want="$1"
  local label="$2"
  has_hit "${want}" || fail "${label}: expected a hit for ${want}, got: ${hits[*]:-none}" "${tmpdir}/scan.err"
}

assert_no_hit() {
  local want="$1"
  local label="$2"
  ! has_hit "${want}" || fail "${label}: unexpected hit for ${want}"
}

# --- the .gitignore parser -------------------------------------------------

# The minimum set is named in the guard rather than counted, because a block
# that still parses can still have lost a pattern. Both ways of losing one have
# to fail closed.
test_parser_fails_closed_on_renamed_heading() {
  local repo
  repo="$(make_repo parser-heading)"
  sed -i 's/^# Secrets safety (defense-in-depth)$/# Secrets safety/' "${repo}/.gitignore"
  : >"${repo}/probe.pem"

  scan "${repo}"
  [[ ${scan_rc} -eq 1 ]] || fail "renamed heading: expected rc 1, got ${scan_rc}" "${tmpdir}/scan.err"
  grep -q 'did not yield the expected patterns' "${tmpdir}/scan.err" ||
    fail "renamed heading: no parser error" "${tmpdir}/scan.err"
  [[ ${#hits[@]} -eq 0 ]] || fail "renamed heading: reported hits from an unparsed block"
  pass
}

# A blank line ends the block, so one inserted mid-block leaves deny non-empty
# while dropping everything after it. A count check cannot see that, which is
# why the guard names the patterns it requires.
test_parser_fails_closed_on_blank_line_mid_block() {
  local repo
  repo="$(make_repo parser-blank)"
  sed -i 's/^# Common SSH\/private key patterns (allow public keys)$/\n&/' "${repo}/.gitignore"
  : >"${repo}/probe.pem"

  scan "${repo}"
  [[ ${scan_rc} -eq 1 ]] || fail "blank line mid-block: expected rc 1, got ${scan_rc}" "${tmpdir}/scan.err"
  grep -q 'missing: id_\* decrypted_\* \*\.dec\.\*' "${tmpdir}/scan.err" ||
    fail "blank line mid-block: error did not name the dropped patterns" "${tmpdir}/scan.err"
  pass
}

# --- secrets_guard_tracked -------------------------------------------------

# Three answers, not two. Collapsing 128 into "not tracked" reads a broken
# repository as a foreign tree and skips the scan.
test_tracked_splits_three_ways() {
  local repo rc
  repo="$(make_repo tracked)"
  : >"${repo}/untracked.txt"

  rc=0
  secrets_guard_tracked "${repo}" README.md || rc=$?
  [[ ${rc} -eq 0 ]] || fail "tracked file: expected rc 0, got ${rc}"

  rc=0
  secrets_guard_tracked "${repo}" untracked.txt || rc=$?
  [[ ${rc} -eq 1 ]] || fail "untracked file: expected rc 1, got ${rc}"

  printf 'garbage, not an index\n' >"${repo}/.git/index"
  rc=0
  secrets_guard_tracked "${repo}" README.md || rc=$?
  [[ ${rc} -eq 128 ]] || fail "corrupt index: expected rc 128, got ${rc}"
  pass
}

# --- the scan --------------------------------------------------------------

test_scan_matches_deny_patterns_and_honours_the_allow_entry() {
  local repo
  repo="$(make_repo deny-allow)"
  : >"${repo}/.env"
  : >"${repo}/probe.pem"
  : >"${repo}/id_ed25519"
  : >"${repo}/id_ed25519.pub"
  : >"${repo}/notes.md"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "deny/allow: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  assert_hit .env "deny/allow"
  assert_hit probe.pem "deny/allow"
  assert_hit id_ed25519 "deny/allow"
  assert_no_hit id_ed25519.pub "deny/allow"
  assert_no_hit notes.md "deny/allow"
  pass
}

# ls-files reports the files inside an ignored directory rather than the
# directory, so a basename-only match copies id_backup/ whole while none of its
# children match anything.
test_scan_walks_every_path_component() {
  local repo
  repo="$(make_repo component-walk)"
  mkdir -p "${repo}/id_backup"
  : >"${repo}/id_backup/notes.txt"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "component walk: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  assert_hit id_backup/notes.txt "component walk"
  pass
}

# The anchored patterns are reduced to their last component, so a stray
# root-level decrypted_* aborts even though git check-ignore matches nothing:
# the anchor scopes git's ignore rule, not this scan.
test_scan_matches_the_anchored_patterns_by_name() {
  local repo
  repo="$(make_repo anchored)"
  : >"${repo}/decrypted_context7.yaml"
  : >"${repo}/probe.dec.txt"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "anchored: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  assert_hit decrypted_context7.yaml "anchored"
  assert_hit probe.dec.txt "anchored"
  pass
}

# ls-files stops at a repository boundary, reporting the directory once and
# never opening it, so nothing inside was ever compared against the block.
# path: has no such boundary, which makes the boundary itself the hit.
test_scan_reports_a_nested_repository_boundary() {
  local repo
  repo="$(make_repo nested-repo)"
  init_repo "${repo}/scratch"
  : >"${repo}/scratch/.env"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "nested repo: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  assert_hit scratch/ "nested repo"
  assert_no_hit scratch/.env "nested repo"
  pass
}

# A plain untracked directory is not a boundary: git descends into it, so only
# what matches the block is reported and result/ or .direnv/ stay clear.
test_scan_leaves_a_plain_untracked_directory_alone() {
  local repo
  repo="$(make_repo plain-dir)"
  mkdir -p "${repo}/.direnv"
  : >"${repo}/.direnv/flake-profile"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "plain dir: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  [[ ${#hits[@]} -eq 0 ]] || fail "plain dir: reported ${hits[*]}"
  pass
}

# Input and output are both NUL delimited so a path holding a newline is
# matched once and reported once. Newline-delimited it was matched as one path
# and reported as two, with the tally inflated to match.
test_scan_round_trips_a_path_holding_a_newline() {
  local repo probe
  repo="$(make_repo newline)"
  probe=$'two\nlines.pem'
  : >"${repo}/${probe}"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "newline: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  [[ ${#hits[@]} -eq 1 ]] || fail "newline: expected 1 hit, got ${#hits[@]}"
  [[ ${hits[0]} == "${probe}" ]] || fail "newline: hit was mangled to ${hits[0]}"
  pass
}

# ls-files stops at a gitlink, but path: copies submodule working trees whole,
# and the block mirrors the submodule's own decrypted_* rules so this pass can
# classify with the same patterns instead of reporting every untracked file.
test_scan_covers_submodule_working_trees() {
  local repo source
  repo="$(make_repo submodule)"
  source="${tmpdir}/submodule-source"
  init_repo "${source}"
  printf '%s\n' 'decrypted_*' >"${source}/.gitignore"
  printf '%s\n' 'submodule' >"${source}/README.md"
  git -C "${source}" add .gitignore README.md
  git -C "${source}" commit -q -m "initial submodule"

  git -C "${repo}" -c protocol.file.allow=always submodule add -q "${source}" secrets
  git -C "${repo}" commit -q -m "add submodule"
  : >"${repo}/secrets/decrypted_probe.yaml"
  : >"${repo}/secrets/build-output.bin"

  scan "${repo}"
  [[ ${scan_rc} -eq 0 ]] || fail "submodule: scan failed with ${scan_rc}" "${tmpdir}/scan.err"
  assert_hit secrets/decrypted_probe.yaml "submodule"
  assert_no_hit secrets/build-output.bin "submodule"
  pass
}

# The preflight proves mktemp is present, not that it works, so a read-only
# TMPDIR still emptied scan and the ls-files redirect failed before git ran. The
# abort then blamed the listing, which is the misattribution the preflight
# exists to prevent. Driven through secrets_guard_paths directly: enforce's own
# mktemp fails first and this call site is never reached through it.
test_scan_fails_closed_on_a_failing_mktemp() {
  local repo stub tool
  repo="$(make_repo scan-mktemp)"
  : >"${repo}/id_ed25519"

  stub="${tmpdir}/stub-failing-mktemp-scan"
  mkdir -p "${stub}"
  for tool in git grep awk rm; do
    ln -sf "$(type -P "${tool}")" "${stub}/${tool}"
  done
  # Present for command -v and creating nothing, unlike the failing rm below,
  # which delegates first: here the missing file is the point.
  printf '%s\n' '#!/bin/sh' 'exit 1' >"${stub}/mktemp"
  chmod +x "${stub}/mktemp"

  PATH="${stub}" scan "${repo}"
  [[ ${scan_rc} -eq 1 ]] ||
    fail "failing mktemp: expected rc 1, got ${scan_rc}" "${tmpdir}/scan.err"
  grep -q '^Error: Creating a temporary file for the scan' "${tmpdir}/scan.err" ||
    fail "failing mktemp: the abort did not name the temp file" "${tmpdir}/scan.err"
  ! grep -q 'Listing untracked files' "${tmpdir}/scan.err" ||
    fail "failing mktemp: blamed a git call that never ran" "${tmpdir}/scan.err"
  pass
}

# --- secrets_guard_enforce -------------------------------------------------

test_enforce_returns_zero_on_a_clean_tree() {
  local repo
  repo="$(make_repo enforce-clean)"

  enforce "${repo}"
  [[ ${enforce_rc} -eq 0 ]] || fail "clean tree: expected rc 0, got ${enforce_rc}" "${tmpdir}/enforce.err"
  pass
}

test_enforce_reports_a_hit_and_names_the_copier() {
  local repo
  repo="$(make_repo enforce-hit)"
  : >"${repo}/id_ed25519"

  enforce "${repo}" "the probe copier"
  [[ ${enforce_rc} -eq 1 ]] || fail "hit: expected rc 1, got ${enforce_rc}" "${tmpdir}/enforce.err"
  grep -q 'the probe copier' "${tmpdir}/enforce.err" ||
    fail "hit: the abort did not name the copier" "${tmpdir}/enforce.err"
  grep -q '^id_ed25519$' "${tmpdir}/enforce.err" ||
    fail "hit: the abort did not list the path" "${tmpdir}/enforce.err"
  pass
}

# The notice and the abort both go to stderr, because cache-coverage.sh writes
# its report to stdout and every skip fires before the report header.
test_enforce_keeps_stdout_clear() {
  local repo
  repo="$(make_repo enforce-streams)"
  : >"${repo}/id_ed25519"

  enforce "${repo}"
  [[ -s ${tmpdir}/enforce.out ]] && fail "hit: wrote to stdout" "${tmpdir}/enforce.out"

  mkdir -p "${tmpdir}/enforce-streams-nongit"
  enforce "${tmpdir}/enforce-streams-nongit"
  [[ ${enforce_rc} -eq 0 ]] || fail "non-git skip: expected rc 0, got ${enforce_rc}" "${tmpdir}/enforce.err"
  [[ -s ${tmpdir}/enforce.out ]] && fail "non-git skip: wrote the notice to stdout" "${tmpdir}/enforce.out"
  grep -q 'is not a git worktree' "${tmpdir}/enforce.err" ||
    fail "non-git skip: no notice on stderr" "${tmpdir}/enforce.err"
  pass
}

# The override is what gets an operator past a scratch tree that holds no
# secret, so both spellings have to clear a tree that otherwise aborts.
test_enforce_honours_the_override() {
  local repo
  repo="$(make_repo enforce-override)"
  : >"${repo}/id_ed25519"

  enforce "${repo}"
  [[ ${enforce_rc} -eq 1 ]] || fail "override control: expected rc 1, got ${enforce_rc}" "${tmpdir}/enforce.err"

  ALLOW_SECRET_COPY=true enforce "${repo}"
  [[ ${enforce_rc} -eq 0 ]] || fail "ALLOW_SECRET_COPY=true: expected rc 0, got ${enforce_rc}" "${tmpdir}/enforce.err"

  ALLOW_SECRET_COPY=1 enforce "${repo}"
  [[ ${enforce_rc} -eq 0 ]] || fail "ALLOW_SECRET_COPY=1: expected rc 0, got ${enforce_rc}" "${tmpdir}/enforce.err"
  pass
}

# A tree that owns the generator and has lost the heading has drifted, and that
# has to fail closed rather than read as a repository that never had the block.
test_enforce_fails_closed_when_the_generator_is_tracked() {
  local repo
  repo="$(make_repo enforce-drift)"
  mkdir -p "${repo}/modules/development"
  : >"${repo}/modules/development/gitignore.nix"
  git -C "${repo}" add modules/development/gitignore.nix
  git -C "${repo}" commit -q -m "add the generator"
  sed -i 's/^# Secrets safety (defense-in-depth)$/# Secrets safety/' "${repo}/.gitignore"

  enforce "${repo}"
  [[ ${enforce_rc} -eq 2 ]] || fail "drift: expected rc 2, got ${enforce_rc}" "${tmpdir}/enforce.err"
  pass
}

# The same shape without the generator is an ordinary repository whose
# .gitignore was never emitted from here, so aborting would name a module it
# does not contain.
test_enforce_skips_a_tree_that_does_not_own_the_generator() {
  local repo
  repo="$(make_repo enforce-foreign)"
  sed -i 's/^# Secrets safety (defense-in-depth)$/# Secrets safety/' "${repo}/.gitignore"
  : >"${repo}/id_ed25519"

  enforce "${repo}"
  [[ ${enforce_rc} -eq 0 ]] || fail "foreign tree: expected rc 0, got ${enforce_rc}" "${tmpdir}/enforce.err"
  grep -q 'is not generated from this repo' "${tmpdir}/enforce.err" ||
    fail "foreign tree: no skip notice" "${tmpdir}/enforce.err"
  pass
}

# Not one of these reports itself usefully from where it runs, which is why they
# are gated ahead of everything rather than left to fail in place. git shared a
# condition with the not-a-worktree skip and returned 0, so the copy went ahead
# unguarded on a tree full of secrets. grep not found returns 127, which negates
# to true and skips the discriminator. A missing awk empties the deny list and
# the parser reports .gitignore drift that has not happened. mktemp leaves the
# temp paths empty, surfacing as a redirect error against a git call that never
# ran. rm closed secrets_guard_paths, so its 127 became that function's status.
# No caller covers every route: build.sh has no required-tool loop and a checkout
# run has no runtimeInputs.
test_enforce_fails_closed_on_a_missing_external() {
  local repo stub missing tool

  repo="$(make_repo enforce-tools)"
  : >"${repo}/id_ed25519"

  # The control: with all five present this tree aborts on the hit, so an rc 2
  # below is the missing tool rather than the fixture.
  enforce "${repo}"
  [[ ${enforce_rc} -eq 1 ]] || fail "tool control: expected rc 1, got ${enforce_rc}" "${tmpdir}/enforce.err"

  # One stub per case, holding every tool the run needs except the one under
  # test, so each is reached on its own rather than reported by an earlier miss.
  # Assigning PATH clears bash's hashed command table, and the assignment is
  # scoped to the call, so the suite's own grep still resolves afterwards.
  for missing in git grep awk mktemp rm; do
    stub="${tmpdir}/stub-no-${missing}"
    mkdir -p "${stub}"
    for tool in git grep awk mktemp rm; do
      if [[ ${tool} != "${missing}" ]]; then
        ln -sf "$(type -P "${tool}")" "${stub}/${tool}"
      fi
    done

    PATH="${stub}" enforce "${repo}"
    [[ ${enforce_rc} -eq 2 ]] ||
      fail "missing ${missing}: expected rc 2, got ${enforce_rc}" "${tmpdir}/enforce.err"
    grep -q "^Error: ${missing} was not found" "${tmpdir}/enforce.err" ||
      fail "missing ${missing}: the abort did not name it" "${tmpdir}/enforce.err"
    # The three ways the old code misread a missing tool: .gitignore drift for
    # awk, a git call that never ran for mktemp, and a worktree reported as none
    # for git, which was the fail-open.
    ! grep -q 'did not yield the expected patterns' "${tmpdir}/enforce.err" ||
      fail "missing ${missing}: blamed the .gitignore block instead" "${tmpdir}/enforce.err"
    ! grep -q 'Listing untracked files' "${tmpdir}/enforce.err" ||
      fail "missing ${missing}: blamed a git call that never ran" "${tmpdir}/enforce.err"
    ! grep -q 'is not a git worktree' "${tmpdir}/enforce.err" ||
      fail "missing ${missing}: skipped a real worktree instead of failing closed" "${tmpdir}/enforce.err"
  done
  pass
}

# rm -f closed secrets_guard_paths, so its status was the scan's status: a
# cleanup that failed discarded a completed hit list and the caller reported the
# guard inoperative. Leaving a temp file behind is not a reason to stop reporting
# secrets, so the scan returns success explicitly.
test_scan_survives_a_failing_cleanup() {
  local repo stub tool

  repo="$(make_repo enforce-cleanup)"
  : >"${repo}/id_ed25519"

  # A real rm that reports failure, so the temp files still go and only the exit
  # status is under test.
  stub="${tmpdir}/stub-failing-rm"
  mkdir -p "${stub}"
  for tool in git grep awk mktemp; do
    ln -sf "$(type -P "${tool}")" "${stub}/${tool}"
  done
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s "$@"\n' "$(type -P rm)"
    printf '%s\n' 'exit 1'
  } >"${stub}/rm"
  chmod +x "${stub}/rm"

  PATH="${stub}" enforce "${repo}"
  [[ ${enforce_rc} -eq 1 ]] ||
    fail "failing cleanup: expected the hit at rc 1, got ${enforce_rc}" "${tmpdir}/enforce.err"
  grep -q '^id_ed25519$' "${tmpdir}/enforce.err" ||
    fail "failing cleanup: the hit list was discarded" "${tmpdir}/enforce.err"
  pass
}

# The hit-list mktemp had no message of its own: an empty hits_file made the
# call below it fail on its redirect, `if !` inverted that into the abort, and
# the run returned 2 having printed nothing the guard wrote. Both callers
# suspend errexit around this function, so no ERR trap covered it either.
test_enforce_fails_closed_on_a_failing_mktemp() {
  local repo stub tool
  repo="$(make_repo enforce-mktemp)"
  : >"${repo}/id_ed25519"

  # The control: with a working mktemp this tree aborts on the hit, so the rc 2
  # below is the temp file rather than the fixture.
  enforce "${repo}"
  [[ ${enforce_rc} -eq 1 ]] ||
    fail "mktemp control: expected rc 1, got ${enforce_rc}" "${tmpdir}/enforce.err"

  stub="${tmpdir}/stub-failing-mktemp-enforce"
  mkdir -p "${stub}"
  for tool in git grep awk rm; do
    ln -sf "$(type -P "${tool}")" "${stub}/${tool}"
  done
  printf '%s\n' '#!/bin/sh' 'exit 1' >"${stub}/mktemp"
  chmod +x "${stub}/mktemp"

  PATH="${stub}" enforce "${repo}"
  [[ ${enforce_rc} -eq 2 ]] ||
    fail "failing mktemp: expected rc 2, got ${enforce_rc}" "${tmpdir}/enforce.err"
  grep -q '^Error: Creating a temporary file for the hit list' "${tmpdir}/enforce.err" ||
    fail "failing mktemp: the abort printed no cause" "${tmpdir}/enforce.err"
  pass
}

# rev-parse answers 128 for a repository git declines to open as well as for a
# directory that is not one, and collapsing both to the skip was a fail-open:
# flake_path_ref_reason selects path: off the .git file alone, so a linked
# worktree that outlived its gitdir was copied unscanned and told it was not a
# worktree. A dangling .git symlink is the same marker, which -e alone drops.
test_enforce_fails_closed_on_an_unopenable_repository() {
  local repo wt dangling
  repo="$(make_repo enforce-unopenable)"
  wt="${tmpdir}/enforce-unopenable-wt"
  git -C "${repo}" worktree add -q -b probe "${wt}"
  : >"${wt}/id_ed25519"

  # The control: while the gitdir is intact this is a worktree and the probe is
  # a hit, so the rc below is the severed gitdir rather than the fixture.
  enforce "${wt}"
  [[ ${enforce_rc} -eq 1 ]] ||
    fail "unopenable control: expected rc 1, got ${enforce_rc}" "${tmpdir}/enforce.err"

  # What a moved or deleted owning checkout leaves behind, and what
  # prune-stale-worktrees.sh reports as broken-gitdir rather than removing.
  rm -r "${repo}/.git/worktrees"
  [[ -f "${wt}/.git" ]] || fail "unopenable: the fixture lost its .git file"

  enforce "${wt}"
  [[ ${enforce_rc} -eq 2 ]] ||
    fail "unopenable: expected rc 2, got ${enforce_rc}" "${tmpdir}/enforce.err"
  grep -q 'carries a .git marker' "${tmpdir}/enforce.err" ||
    fail "unopenable: the abort did not name the marker" "${tmpdir}/enforce.err"
  ! grep -q 'is not a git worktree' "${tmpdir}/enforce.err" ||
    fail "unopenable: skipped a broken repository as a foreign tree" "${tmpdir}/enforce.err"

  dangling="${tmpdir}/enforce-unopenable-symlink"
  mkdir -p "${dangling}"
  ln -s "${tmpdir}/gitdir-that-is-gone" "${dangling}/.git"
  enforce "${dangling}"
  [[ ${enforce_rc} -eq 2 ]] ||
    fail "dangling .git: expected rc 2, got ${enforce_rc}" "${tmpdir}/enforce.err"
  pass
}

# Tracked but absent is the state the generator can produce, so it fails closed
# where a tree that simply never had one is skipped.
test_enforce_splits_a_missing_gitignore_by_tracked_state() {
  local repo bare
  repo="$(make_repo enforce-absent)"
  rm "${repo}/.gitignore"

  enforce "${repo}"
  [[ ${enforce_rc} -eq 2 ]] || fail "tracked but absent: expected rc 2, got ${enforce_rc}" "${tmpdir}/enforce.err"

  bare="${tmpdir}/enforce-nogitignore"
  init_repo "${bare}"
  printf '%s\n' readme >"${bare}/README.md"
  git -C "${bare}" add README.md
  git -C "${bare}" commit -q -m "initial commit"

  enforce "${bare}"
  [[ ${enforce_rc} -eq 0 ]] || fail "never had one: expected rc 0, got ${enforce_rc}" "${tmpdir}/enforce.err"
  grep -q 'has no .gitignore' "${tmpdir}/enforce.err" ||
    fail "never had one: no skip notice" "${tmpdir}/enforce.err"
  pass
}

test_parser_fails_closed_on_renamed_heading
test_parser_fails_closed_on_blank_line_mid_block
test_tracked_splits_three_ways
test_scan_matches_deny_patterns_and_honours_the_allow_entry
test_scan_walks_every_path_component
test_scan_matches_the_anchored_patterns_by_name
test_scan_reports_a_nested_repository_boundary
test_scan_leaves_a_plain_untracked_directory_alone
test_scan_round_trips_a_path_holding_a_newline
test_scan_covers_submodule_working_trees
test_scan_fails_closed_on_a_failing_mktemp
test_enforce_returns_zero_on_a_clean_tree
test_enforce_reports_a_hit_and_names_the_copier
test_enforce_keeps_stdout_clear
test_enforce_honours_the_override
test_enforce_fails_closed_when_the_generator_is_tracked
test_enforce_skips_a_tree_that_does_not_own_the_generator
test_enforce_fails_closed_on_a_missing_external
test_scan_survives_a_failing_cleanup
test_enforce_fails_closed_on_a_failing_mktemp
test_enforce_fails_closed_on_an_unopenable_repository
test_enforce_splits_a_missing_gitignore_by_tracked_state

printf '%d passed\n' "${tests_passed}"
