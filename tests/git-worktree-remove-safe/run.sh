#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/git-worktree-remove-safe.sh"

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

init_repo() {
  local repo
  repo="$1"

  git init -q "${repo}"
  git -C "${repo}" config user.email tests@example.invalid
  git -C "${repo}" config user.name "git-worktree-remove-safe tests"
}

commit_all() {
  local repo message
  repo="$1"
  message="$2"

  git -C "${repo}" add .
  git -C "${repo}" commit -q -m "${message}"
}

make_submodule_source() {
  local name submodule_source
  name="$1"
  submodule_source="${tmpdir}/${name}-submodule-source"

  mkdir -p "${submodule_source}"
  init_repo "${submodule_source}"
  printf '%s\n' '.pre-commit-config.yaml' >"${submodule_source}/.gitignore"
  printf '%s\n' "submodule ${name}" >"${submodule_source}/README.md"
  commit_all "${submodule_source}" "initial submodule"

  printf '%s\n' "${submodule_source}"
}

add_submodule() {
  local repo submodule_source
  repo="$1"
  submodule_source="$2"

  git -C "${repo}" -c protocol.file.allow=always submodule add -q "${submodule_source}" deps/sub
  commit_all "${repo}" "add submodule"
}

assert_worktree_removed() {
  local repo worktree
  repo="$1"
  worktree="$2"

  if git -C "${repo}" worktree list --porcelain | grep -Fxq "worktree ${worktree}"; then
    printf 'FAIL: worktree is still registered: %s\n' "${worktree}" >&2
    exit 1
  fi
  if [[ -e ${worktree} ]]; then
    printf 'FAIL: worktree path still exists: %s\n' "${worktree}" >&2
    exit 1
  fi
}

assert_worktree_kept() {
  local repo worktree
  repo="$1"
  worktree="$2"

  if ! git -C "${repo}" worktree list --porcelain | grep -Fxq "worktree ${worktree}"; then
    printf 'FAIL: worktree was removed: %s\n' "${worktree}" >&2
    exit 1
  fi
  if [[ ! -d ${worktree} ]]; then
    printf 'FAIL: worktree path is missing: %s\n' "${worktree}" >&2
    exit 1
  fi
}

test_ignored_root_precommit_config_allows_removal() {
  local repo worktree
  repo="${tmpdir}/ignored-root"
  worktree="${tmpdir}/ignored-root-worktree"

  mkdir -p "${repo}"
  init_repo "${repo}"
  printf '%s\n' '.pre-commit-config.yaml' >"${repo}/.gitignore"
  printf '%s\n' root >"${repo}/README.md"
  commit_all "${repo}" "initial root"

  git -C "${repo}" worktree add -q -b ignored-root-test "${worktree}"
  printf '%s\n' generated >"${worktree}/.pre-commit-config.yaml"

  (cd "${repo}" && "${SUT}" "${worktree}")
  assert_worktree_removed "${repo}" "${worktree}"
}

test_tracked_root_precommit_config_refuses_removal_with_submodules() {
  local repo submodule_source worktree stderr_file
  repo="${tmpdir}/tracked-root"
  worktree="${tmpdir}/tracked-root-worktree"
  stderr_file="${tmpdir}/tracked-root.stderr"

  mkdir -p "${repo}"
  init_repo "${repo}"
  printf '%s\n' tracked >"${repo}/.pre-commit-config.yaml"
  printf '%s\n' root >"${repo}/README.md"
  commit_all "${repo}" "initial root"
  submodule_source="$(make_submodule_source tracked-root)"
  add_submodule "${repo}" "${submodule_source}"

  git -C "${repo}" worktree add -q -b tracked-root-test "${worktree}"
  git -C "${worktree}" -c protocol.file.allow=always submodule update -q --init --recursive
  printf '%s\n' modified >"${worktree}/.pre-commit-config.yaml"

  if (cd "${repo}" && "${SUT}" "${worktree}") 2>"${stderr_file}"; then
    printf 'FAIL: tracked .pre-commit-config.yaml did not block removal\n' >&2
    exit 1
  fi
  assert_worktree_kept "${repo}" "${worktree}"
}

test_ignored_submodule_precommit_config_allows_removal() {
  local repo submodule_source worktree
  repo="${tmpdir}/ignored-submodule"
  worktree="${tmpdir}/ignored-submodule-worktree"

  mkdir -p "${repo}"
  init_repo "${repo}"
  printf '%s\n' root >"${repo}/README.md"
  commit_all "${repo}" "initial root"
  submodule_source="$(make_submodule_source ignored-submodule)"
  add_submodule "${repo}" "${submodule_source}"

  git -C "${repo}" worktree add -q -b ignored-submodule-test "${worktree}"
  git -C "${worktree}" -c protocol.file.allow=always submodule update -q --init --recursive
  printf '%s\n' generated >"${worktree}/deps/sub/.pre-commit-config.yaml"

  (cd "${repo}" && "${SUT}" "${worktree}")
  assert_worktree_removed "${repo}" "${worktree}"
}

test_ignored_root_precommit_config_allows_removal
test_tracked_root_precommit_config_refuses_removal_with_submodules
test_ignored_submodule_precommit_config_allows_removal

printf '3 passed\n'
