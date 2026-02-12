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

rewrite_hook_script() {
  local hook_file="$1"
  local hook_type="$2"
  local install_python_line tmp_file

  install_python_line="$(rg -m1 '^INSTALL_PYTHON=' "${hook_file}" || true)"
  if [[ -z ${install_python_line} ]]; then
    install_python_line="INSTALL_PYTHON="
  fi

  tmp_file="$(mktemp)"
  if ! awk \
    -v install_line="${install_python_line}" \
    -v hook_type="${hook_type}" \
    '
      BEGIN {
        in_templated = 0
        saw_start = 0
        saw_end = 0
      }

      $0 == "# start templated" {
        saw_start = 1
        in_templated = 1
        print "# start templated"
        print install_line
        print "REPO_TOP=\"$(git rev-parse --show-toplevel 2>/dev/null || pwd)\""
        print "LOCAL_CONFIG=\"${REPO_TOP}/.pre-commit-config.yaml\""
        print "FALLBACK_CONFIG=\"$(git rev-parse --git-path hooks)/pre-commit-config.yaml\""
        print "if [[ -f \"${LOCAL_CONFIG}\" ]]; then"
        print "  HOOK_CONFIG=\"${LOCAL_CONFIG}\""
        print "elif [[ -f \"${FALLBACK_CONFIG}\" ]]; then"
        print "  HOOK_CONFIG=\"${FALLBACK_CONFIG}\""
        print "else"
        print "  printf '\''%s\\n'\'' \"pre-commit hook: missing .pre-commit-config.yaml; run '\''nix develop'\'' in this worktree.\" >&2"
        print "  exit 1"
        print "fi"
        print "ARGS=(hook-impl --config=\"${HOOK_CONFIG}\" --hook-type=" hook_type ")"
        next
      }

      $0 == "# end templated" && in_templated == 1 {
        saw_end = 1
        in_templated = 0
        print "# end templated"
        next
      }

      in_templated == 0 {
        print $0
      }

      END {
        if (saw_start != 1 || saw_end != 1) {
          exit 2
        }
      }
    ' "${hook_file}" >"${tmp_file}"; then
    error_msg "failed to rewrite templated section in ${hook_file}"
    rm -f "${tmp_file}"
    exit 1
  fi

  mv "${tmp_file}" "${hook_file}"
  chmod +x "${hook_file}"
}

main() {
  require_cmd git
  require_cmd readlink
  require_cmd rg
  require_cmd awk

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error_msg "must be run from within a git worktree"
    exit 1
  fi

  local repo_root git_common_dir hooks_dir config_file abs_config fallback_config hook hook_file
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

  # Linked worktrees use a .git file, so relative `.git/hooks` is not portable.
  # Point hooksPath at the shared git-common-dir hooks directory.
  mkdir -p "${hooks_dir}"
  git config core.hooksPath "${hooks_dir}"
  fallback_config="${hooks_dir}/pre-commit-config.yaml"
  cp -f "${abs_config}" "${fallback_config}"

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

    rewrite_hook_script "${hook_file}" "${hook}"

    if ! rg -F --quiet -- 'LOCAL_CONFIG="${REPO_TOP}/.pre-commit-config.yaml"' "${hook_file}"; then
      error_msg "hook ${hook_file} missing local config resolution logic"
      exit 1
    fi

    if ! rg -F --quiet -- 'FALLBACK_CONFIG="$(git rev-parse --git-path hooks)/pre-commit-config.yaml"' "${hook_file}"; then
      error_msg "hook ${hook_file} missing shared fallback config logic"
      exit 1
    fi

    if ! rg -F --quiet -- "--hook-type=${hook}" "${hook_file}"; then
      error_msg "hook ${hook_file} missing expected hook type ${hook}"
      exit 1
    fi
  done
}

main "$@"
