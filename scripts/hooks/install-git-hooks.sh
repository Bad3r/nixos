#!/usr/bin/env bash
set -Eeu -o pipefail

error_msg() {
  printf 'install-git-hooks: %s\n' "$1" >&2
}

main() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error_msg "must be run from within a git worktree"
    exit 1
  fi

  local repo_root git_common_dir hooks_dir src name dest
  repo_root="$(git rev-parse --show-toplevel)"
  git_common_dir="$(readlink -f "$(git rev-parse --git-common-dir)")"
  hooks_dir="${git_common_dir}/hooks"

  cd "${repo_root}"

  if [[ ! -d .githooks ]]; then
    return 0
  fi

  mkdir -p "${hooks_dir}"

  shopt -s nullglob
  for src in .githooks/*; do
    [[ -f ${src} ]] || continue
    name="$(basename "${src}")"
    dest="${hooks_dir}/${name}"
    install -m 0755 "${src}" "${dest}"
  done
}

main "$@"
