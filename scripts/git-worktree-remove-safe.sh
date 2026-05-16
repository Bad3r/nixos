#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"

usage() {
  printf 'usage: %s <worktree-path>\n' "${prog_name}" >&2
}

error_msg() {
  printf '%s: %s\n' "${prog_name}" "$1" >&2
}

git_common_dir() {
  local repo_root common_dir
  repo_root="$1"
  common_dir="$(git -C "${repo_root}" rev-parse --git-common-dir)"
  if [[ ${common_dir} != /* ]]; then
    common_dir="${repo_root}/${common_dir}"
  fi
  readlink -f "${common_dir}"
}

resolve_worktree_root() {
  local target_path
  target_path="$1"
  if [[ ! -d ${target_path} ]]; then
    error_msg "worktree path does not exist: ${target_path}"
    exit 1
  fi
  if ! git -C "${target_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error_msg "path is not inside a git worktree: ${target_path}"
    exit 1
  fi
  readlink -f "$(git -C "${target_path}" rev-parse --show-toplevel)"
}

require_registered_unlocked_worktree() {
  local repo_root worktree_path current_path in_target found locked entry
  repo_root="$1"
  worktree_path="$2"
  current_path=""
  in_target=false
  found=false
  locked=false

  while IFS= read -r -d '' entry; do
    case "${entry}" in
    worktree\ *)
      current_path="$(readlink -f "${entry#worktree }")"
      if [[ ${current_path} == "${worktree_path}" ]]; then
        in_target=true
        found=true
      else
        in_target=false
      fi
      ;;
    locked*)
      if [[ ${in_target} == true ]]; then
        locked=true
      fi
      ;;
    esac
  done < <(git -C "${repo_root}" worktree list --porcelain -z)

  if [[ ${found} != true ]]; then
    error_msg "path is not a registered worktree for this repository: ${worktree_path}"
    exit 1
  fi
  if [[ ${locked} == true ]]; then
    error_msg "refusing to remove locked worktree: ${worktree_path}"
    exit 1
  fi
}

require_clean_worktree() {
  local worktree_path status submodule_status
  worktree_path="$1"

  status="$(git -C "${worktree_path}" status --porcelain=v1 --untracked-files=all --ignored=matching)"
  if [[ -n ${status} ]]; then
    error_msg "refusing to remove worktree with dirty, untracked, or ignored local state: ${worktree_path}"
    printf '%s\n' "${status}" >&2
    exit 1
  fi

  # shellcheck disable=SC2016 # This body runs inside git-submodule foreach.
  if ! submodule_status="$(
    git -C "${worktree_path}" submodule foreach --quiet --recursive '
      status="$(git status --porcelain=v1 --untracked-files=all --ignored=matching)"
      if test -n "${status}"; then
        printf "%s\n%s\n" "${displaypath}" "${status}"
        exit 1
      fi
    ' 2>&1
  )"; then
    error_msg "refusing to remove worktree with dirty submodule state: ${worktree_path}"
    printf '%s\n' "${submodule_status}" >&2
    exit 1
  fi
}

main() {
  local repo_root target_arg worktree_path repo_common_dir worktree_common_dir remove_output remove_status

  if [[ $# -ne 1 ]]; then
    usage
    exit 64
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error_msg "must be run from within the repository that owns the worktree"
    exit 1
  fi

  repo_root="$(git rev-parse --show-toplevel)"
  target_arg="$1"
  worktree_path="$(resolve_worktree_root "${target_arg}")"
  repo_root="$(readlink -f "${repo_root}")"
  repo_common_dir="$(git_common_dir "${repo_root}")"
  worktree_common_dir="$(git_common_dir "${worktree_path}")"

  if [[ ${repo_common_dir} != "${worktree_common_dir}" ]]; then
    error_msg "target belongs to a different repository: ${worktree_path}"
    exit 1
  fi
  if [[ ${worktree_path} == "${repo_root}" ]]; then
    error_msg "refusing to remove the worktree running this helper: ${worktree_path}"
    exit 1
  fi

  require_registered_unlocked_worktree "${repo_root}" "${worktree_path}"
  require_clean_worktree "${worktree_path}"

  if remove_output="$(git -C "${repo_root}" worktree remove "${worktree_path}" 2>&1)"; then
    if [[ -n ${remove_output} ]]; then
      printf '%s\n' "${remove_output}" >&2
    fi
    exit 0
  else
    remove_status="$?"
  fi

  if [[ ${remove_output} == *"working trees containing submodules cannot be moved or removed"* ]]; then
    error_msg "worktree contains submodules; retrying with --force after clean checks: ${worktree_path}"
    git -C "${repo_root}" worktree remove --force "${worktree_path}"
    exit 0
  fi

  printf '%s\n' "${remove_output}" >&2
  exit "${remove_status}"
}

main "$@"
