#!/usr/bin/env bash
# shellcheck shell=bash
# Covers scripts/lib/flake-ref.sh, the one predicate build.sh and
# scripts/cache-coverage.sh both read to decide whether a tree gets a path:
# reference. It is also the gate on the secrets guard: ensure_no_ignored_secrets
# returns 0 whenever PATH_REF_REASON is empty, and cache-coverage.sh runs the
# guard only when the reference it derived from that value starts with path:.
# The guard itself has a suite; the predicate deciding whether the guard applies
# had none, and hand-kept copies of this rule have already drifted once (before
# 65e8afbe the report hardcoded path: and copied unguarded on every run).
#
# The subject is sourced rather than executed. It has no shebang and defines one
# function for both callers to share, and that function runs no external at all,
# so every case here is a marker shape plus an argument.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/lib/flake-ref.sh"

if [[ ! -f ${SUT} ]]; then
  printf 'run.sh: SUT not found at %s\n' "${SUT}" >&2
  exit 2
fi
# shellcheck source-path=SCRIPTDIR source=../../scripts/lib/flake-ref.sh disable=SC1091
source "${SUT}"

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

# Only the linked-worktree case reaches git, and it does so to produce the
# marker rather than to read one. Isolated anyway, since a worktree inherits
# whatever the operator's configuration says about hooks and templates.
export HOME="${tmpdir}/home"
mkdir -p "${HOME}"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0

tests_passed=0
tests_ran=()

pass() {
  tests_passed=$((tests_passed + 1))
  # The caller's name, so the tail of this file can assert that every case
  # defined here actually ran rather than trusting the invocation list.
  tests_ran+=("${FUNCNAME[1]}")
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# The reason string is the assertion, not a boolean: build.sh prints it in the
# notice that explains the missing system.configurationRevision, so which of the
# two branches answered is operator-visible and has to stay distinguishable.
assert_reason() {
  local label="$1"
  local dir="$2"
  local allow_dirty="$3"
  local want="$4"
  local got
  got="$(flake_path_ref_reason "${dir}" "${allow_dirty}")"
  [[ ${got} == "${want}" ]] || fail "${label}: expected [${want}], got [${got}]"
}

# A primary checkout with the real thing: git writes .git as a directory here,
# which is the shape that must not take path:, since path: would copy the whole
# history into the store and lose self.rev with it.
make_primary() {
  local repo="${tmpdir}/$1"

  mkdir -p "${repo}"
  git init -q -b main "${repo}"
  git -C "${repo}" config user.email tests@example.invalid
  git -C "${repo}" config user.name "flake-ref tests"
  printf '%s\n' readme >"${repo}/README.md"
  git -C "${repo}" add README.md
  git -C "${repo}" commit -q -m "initial commit"
  printf '%s\n' "${repo}"
}

# --- the two reasons -------------------------------------------------------

# The marker is produced by git rather than written by hand, because the whole
# branch rests on which shape `git worktree add` leaves behind: a plain file
# holding `gitdir: ...`, never a symlink and never a directory.
test_a_linked_worktree_takes_path() {
  local primary linked
  primary="$(make_primary linked-primary)"
  linked="${tmpdir}/linked-worktree"
  git -C "${primary}" worktree add -q -b feature "${linked}"

  [[ -f "${linked}/.git" && ! -L "${linked}/.git" ]] ||
    fail "linked worktree: git did not write .git as a plain file"
  assert_reason "linked worktree" "${linked}" false "linked worktree"
  pass
}

test_a_primary_checkout_keeps_the_bare_ref() {
  local primary
  primary="$(make_primary primary-bare)"

  [[ -d "${primary}/.git" ]] || fail "primary checkout: git did not write .git as a directory"
  assert_reason "primary checkout" "${primary}" false ""
  pass
}

# No git worktree at all, which is what --flake-dir can point at. Nothing is
# tracked there, so the bare ref has nothing to filter and path: would only add
# the copy.
test_a_non_git_directory_keeps_the_bare_ref() {
  local dir="${tmpdir}/plain"
  mkdir -p "${dir}"

  assert_reason "non-git directory" "${dir}" false ""
  pass
}

test_allow_dirty_takes_path_in_a_primary_checkout() {
  local primary
  primary="$(make_primary primary-dirty)"

  assert_reason "allow-dirty as true" "${primary}" true "allow-dirty"
  assert_reason "allow-dirty as 1" "${primary}" 1 "allow-dirty"
  pass
}

# The flag is tested first, so it names itself even where the marker would have
# selected path: anyway. build.sh reports one reason, and the one it reports is
# the one that would still apply if the other went away.
test_allow_dirty_outranks_the_worktree_marker() {
  local primary linked
  primary="$(make_primary outrank-primary)"
  linked="${tmpdir}/outrank-worktree"
  git -C "${primary}" worktree add -q -b outrank "${linked}"

  assert_reason "allow-dirty over marker" "${linked}" true "allow-dirty"
  pass
}

# Exact match, not truthiness. Both callers take ALLOW_DIRTY from the
# environment, so an operator can spell it anything; build.sh's own message
# names --allow-dirty and ALLOW_DIRTY=1, and ensure_clean_git_tree gates on the
# same two literals, so a third spelling is refused consistently rather than
# half-honoured by whichever check is more generous.
test_allow_dirty_accepts_only_the_two_documented_spellings() {
  local dir="${tmpdir}/spellings"
  local value
  mkdir -p "${dir}"

  for value in yes TRUE True on 0 false ""; do
    assert_reason "allow-dirty as ${value:-empty}" "${dir}" "${value}" ""
  done
  pass
}

# --- what the marker test does and does not resolve ------------------------

# -f follows the link, so a .git symlink pointing at a file reads as the linked
# worktree it names. git never writes this, but a hand-relocated marker does,
# and it is the shape where reading through is right.
test_a_dot_git_symlink_to_a_file_takes_path() {
  local dir="${tmpdir}/symlink-to-file"
  mkdir -p "${dir}"
  printf 'gitdir: %s/elsewhere\n' "${tmpdir}" >"${tmpdir}/relocated-gitfile"
  ln -s "${tmpdir}/relocated-gitfile" "${dir}/.git"

  assert_reason "symlink to a file" "${dir}" false "linked worktree"
  pass
}

# Following it the other way lands on a directory, which is the primary-checkout
# answer: Lix stats the marker the same way, so the bare ref works there.
# secrets_guard_enforce classifies the same marker with -e || -L, and that is
# not this question: it runs only after git has already refused to open the
# tree, to tell a broken repository from a foreign one. Pinned so the two are
# read as separate answers rather than resynced by mistake.
test_a_dot_git_symlink_to_a_directory_keeps_the_bare_ref() {
  local dir="${tmpdir}/symlink-to-dir"
  mkdir -p "${dir}" "${tmpdir}/relocated-gitdir"
  ln -s "${tmpdir}/relocated-gitdir" "${dir}/.git"

  assert_reason "symlink to a directory" "${dir}" false ""
  pass
}

test_a_dangling_dot_git_symlink_keeps_the_bare_ref() {
  local dir="${tmpdir}/symlink-dangling"
  mkdir -p "${dir}"
  ln -s "${tmpdir}/absent-gitdir" "${dir}/.git"

  assert_reason "dangling symlink" "${dir}" false ""
  pass
}

test_a_linked_worktree_takes_path
test_a_primary_checkout_keeps_the_bare_ref
test_a_non_git_directory_keeps_the_bare_ref
test_allow_dirty_takes_path_in_a_primary_checkout
test_allow_dirty_outranks_the_worktree_marker
test_allow_dirty_accepts_only_the_two_documented_spellings
test_a_dot_git_symlink_to_a_file_takes_path
test_a_dot_git_symlink_to_a_directory_keeps_the_bare_ref
test_a_dangling_dot_git_symlink_keeps_the_bare_ref

# Asserted, not merely reported, for the reason tests/secrets-guard/run.sh
# states at the same place: the invocation list is hand-maintained, so a dropped
# line would cut coverage while the suite still exits 0 and prints a smaller
# number that nothing compares against.
missing=()
while IFS= read -r line; do
  fn="${line##* }"
  [[ ${fn} == test_* ]] || continue
  ran=0
  for name in "${tests_ran[@]}"; do
    if [[ ${name} == "${fn}" ]]; then
      ran=1
      break
    fi
  done
  [[ ${ran} -eq 1 ]] || missing+=("${fn}")
done < <(declare -F)

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'run.sh: defined but never reached pass: %s\n' "${missing[*]}" >&2
  printf 'run.sh: add it to the invocation list above, or delete it.\n' >&2
  exit 1
fi

printf '%d passed\n' "${tests_passed}"
