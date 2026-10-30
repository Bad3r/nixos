#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"

usage() {
  printf 'usage: %s [--force] <worktree-path>\n' "${prog_name}"
}

help() {
  usage
  cat <<'EOF_HELP'

Remove a linked git worktree after checking that it holds no local state.

Runs from any directory against the repository that owns the worktree. Refuses
the primary worktree, the worktree containing the current directory, and dirty,
untracked, or non-disposable ignored files, in the worktree or any submodule.
Git itself refuses a locked worktree.

Options:
  -f, --force  Skip the dirty-state checks and discard that state, printing it
               to stderr first. The primary-worktree and current-directory checks
               still apply.
  -h, --help   Show this help.
EOF_HELP
}

error_msg() {
  printf '%s: %s\n' "${prog_name}" "$1" >&2
}

# Keep untracked state, ignored secrets, and local config visible; drop only ignored cleanup noise.
readonly disposable_status_sed_script='\#^!! (scripts/hooks/pre-commit-config\.yaml|\.pre-commit-config\.yaml)$#d
\#^!! result([.-][^/]*)?(/.*)?/?$#d
\#^!! (.*/)?[^/]*\.log$#d
\#^!! (.*/)?\.?log(/.*)?/?$#d
\#^!! (.*/)?[^/]*[cC][aA][cC][hH][eE][^/]*/.*$#d
\#^!! (.*/)?(\.clj-kondo|\.lsp|\.specify|\.direnv|\.kiro|tmp|\.tmp|\.code|\.tox|\.nox|\.vscode|\.idea|node_modules|\.wrangler)(/.*)?/?$#d
\#^!! (.*/)?[^/]*\.pyc$#d
\#^!! (.*/)?(\.DS_Store|Thumbs\.db)$#d
\#^!! (.*/)?[^/]*\.(swp|swo|tgz)$#d
\#^!! (.*/)?[^/]*~$#d'
export disposable_status_sed_script

filter_disposable_status() {
  sed -E "${disposable_status_sed_script}"
}

primary_worktree_root() {
  local entry
  entry="$(git -C "$1" worktree list --porcelain | head -n 1)"
  readlink -f "${entry#worktree }"
}

# Porcelain status of the worktree and its submodules, submodule paths prefixed.
# Lines matching sed script $2 are dropped; an empty script keeps everything.
worktree_state() {
  local sed_script
  sed_script="$2"
  export sed_script

  git -C "$1" status --porcelain=v1 --untracked-files=all --ignored=matching |
    sed -E "${sed_script}"
  # shellcheck disable=SC2016 # This body runs inside git-submodule foreach.
  git -C "$1" submodule foreach --quiet --recursive '
    git status --porcelain=v1 --untracked-files=all --ignored=matching |
      sed -E "${sed_script}" |
      sed "s#^\(...\)#\1${displaypath}/#"
  '
}

require_clean_worktree() {
  local state
  state="$(worktree_state "$1" "${disposable_status_sed_script}")"
  if [[ -n ${state} ]]; then
    error_msg "refusing to remove worktree with dirty, untracked, or ignored local state: $1"
    printf '%s\n' "${state}" >&2
    exit 1
  fi
}

report_discarded_state() {
  local state
  state="$(worktree_state "$1" "")"
  if [[ -n ${state} ]]; then
    error_msg "--force discards this state in $1:"
    printf '%s\n' "${state}" >&2
  fi
}

main() {
  local repo_root worktree_path
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      help
      exit 0
      ;;
    -f | --force)
      force=true
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      error_msg "unknown option: $1"
      usage >&2
      exit 64
      ;;
    *)
      break
      ;;
    esac
  done

  if [[ $# -ne 1 ]]; then
    usage >&2
    exit 64
  fi

  worktree_path="$(git -C "$1" rev-parse --show-toplevel)"
  worktree_path="$(readlink -f "${worktree_path}")"
  repo_root="$(primary_worktree_root "${worktree_path}")"

  if [[ ${worktree_path} == "${repo_root}" ]]; then
    error_msg "refusing to remove the primary worktree: ${worktree_path}"
    exit 1
  fi
  if [[ $(readlink -f .)/ == "${worktree_path}"/* ]]; then
    error_msg "refusing to remove the worktree containing the current directory: ${worktree_path}"
    exit 1
  fi

  if [[ ${force} == true ]]; then
    report_discarded_state "${worktree_path}"
  else
    require_clean_worktree "${worktree_path}"
  fi

  git -C "${repo_root}" worktree remove --force "${worktree_path}"
}

main "$@"
