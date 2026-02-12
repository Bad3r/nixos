#!/usr/bin/env bash
set -Eeu -o pipefail

error_msg() {
  printf 'pre-commit hook sync: %s\n' "$1" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    error_msg "required command not found: ${cmd}"
    exit 1
  fi
}

main() {
  require_cmd git
  require_cmd readlink
  require_cmd rg
  require_cmd sed

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error_msg "must be run from within a git worktree"
    exit 1
  fi

  local repo_root git_common_dir hooks_dir config_file abs_config escaped_abs_config hook hook_file
  repo_root="$(git rev-parse --show-toplevel)"
  git_common_dir="$(readlink -f "$(git rev-parse --git-common-dir)")"
  hooks_dir="${git_common_dir}/hooks"
  config_file=".pre-commit-config.yaml"

  cd "${repo_root}"

  if [[ ! -e ${config_file} ]]; then
    error_msg "${config_file} is missing. Run 'nix develop' to generate it, then retry."
    exit 1
  fi

  abs_config="$(readlink -f "${config_file}" 2>/dev/null || true)"
  if [[ -z ${abs_config} || ! -f ${abs_config} ]]; then
    error_msg "unable to resolve ${config_file} to a valid file (resolved: '${abs_config:-<empty>}')"
    exit 1
  fi

  case "${abs_config}" in
  /*) ;;
  *)
    error_msg "resolved config path is not absolute: ${abs_config}"
    exit 1
    ;;
  esac

  escaped_abs_config="$(printf '%s\n' "${abs_config}" | sed 's/[\\/&]/\\&/g')"

  # Linked worktrees use a .git file, so relative `.git/hooks` is not portable.
  # Point hooksPath at the shared git-common-dir hooks directory.
  mkdir -p "${hooks_dir}"
  git config core.hooksPath "${hooks_dir}"

  for hook in pre-commit pre-push; do
    hook_file="${hooks_dir}/${hook}"
    if [[ ! -f ${hook_file} ]]; then
      error_msg "expected hook file is missing: ${hook_file}"
      exit 1
    fi

    if ! rg -F --quiet -- "hook-impl" "${hook_file}"; then
      error_msg "hook file does not look like a pre-commit-managed script: ${hook_file}"
      exit 1
    fi

    sed -E -i "s|--config=[^[:space:]]+|--config=${escaped_abs_config}|g" "${hook_file}"

    if ! rg -F --quiet -- "--config=${abs_config}" "${hook_file}"; then
      error_msg "hook ${hook_file} does not reference expected config path ${abs_config}"
      exit 1
    fi
  done
}

main "$@"
