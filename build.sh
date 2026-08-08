#!/usr/bin/env bash
# Validation and build helper for this flake
# Common Usage:
#   ./build.sh [--offline] [--fallback] [--verbose]
##
## This script performs validation (git hooks and flake checks),
## then deploys via `nh os` after validation succeeds. It never disables the
## sandbox or performs GC/optimise,
## and it does not mutate repo file ownership. Keep permission and state
## management declarative in NixOS modules.
set -Eeu -o pipefail

# Resolved against this script, not FLAKE_DIR: -p can point the build at another
# flake, and the guard shared with scripts/cache-coverage.sh ships with the
# script rather than with the tree being built.
# SC1091 is disabled the way scripts/cache-coverage.sh disables it: the hook
# passes only the staged files, so staging this one without the library leaves
# the source unfollowable. source-path still gives a run that names both files
# the cross-file check.
# shellcheck source-path=SCRIPTDIR source=scripts/lib/secrets-guard.sh disable=SC1091
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scripts/lib/secrets-guard.sh"

# Initialize variables with defaults
FLAKE_DIR="${PWD}"
TARGET_HOST="$(hostname)"
OFFLINE=false
VERBOSE=false
ALLOW_DIRTY=${ALLOW_DIRTY:-false}
ALLOW_SECRET_COPY=${ALLOW_SECRET_COPY:-false}
AUTO_UPDATE=false
SKIP_HOOKS=false
SKIP_CHECK=false
SKIP_SCORE=false
SKIP_FIRMWARE=false
KEEP_GOING=false
REPAIR=false
FALLBACK=false
BOOTSTRAP_CACHES=false
CACHE_COVERAGE=false
ACTION="switch" # default action after build: switch | boot
BUILD_FLAGS=()
NH_CMD=()
LOG_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/nixos-build"
LOG_FILE=""
# Superset of Lix names (pipe-operator, flake-self-attrs) and the CppNix
# spelling (pipe-operators) so the first build after checkout works from a
# host still running CppNix; each implementation warns about the other's
# names. NIX_CONFIG is not check-phased, unlike nix.settings.
BOOTSTRAP_EXPERIMENTAL_FEATURES="nix-command flakes pipe-operator pipe-operators flake-self-attrs"
# Colors for output (readonly constants)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

# Function to display help
show_help() {
  printf "Usage: %s [OPTIONS]

NixOS system build and deployment script

Options:
  -p, --flake-dir PATH   Set configuration directory (default: %s)
  -t, --host HOST        Specify target hostname (default: %s)
  -o, --offline          Build in offline mode
  -v, --verbose          Enable verbose output
      --boot             Install as next-boot generation (do not activate now)
      --allow-dirty      Allow running with a dirty git worktree (not recommended)
      --allow-secret-copy Build even when ignored files matching the .gitignore secrets block are present
      --update           Run 'nix flake metadata --refresh' and 'nix flake update' before building
      --skip-hooks       Skip the pre-commit validation
      --skip-check       Skip the 'nix flake check' validation step
      --skip-all         Skip all validation steps (pre-commit hooks, flake check)
      --skip-firmware    Skip firmware refresh/check/apply after successful switch
      --keep-going       Continue building despite failures
      --repair           Repair corrupted store paths during build
      --fallback         Build from source if binary substitutes fail
      --bootstrap        Replace the substituter list with the bootstrap
                         caches for a first build
      --cache-coverage   Fail before deploying when the target host closure
                         has unexpected local source builds
                         (scripts/cache-coverage.sh)
  -h, --help             Show this help message

Logs:
  Each run is recorded to %s/build-<timestamp>-<pid>.log

  Usage Example:
  ${0} --offline
" "${0##*/}" "${PWD}" "$(hostname)" "${LOG_DIR}"
}

# Status messages with printf
status_msg() {
  local color="$1"
  local msg="$2"
  printf "%b==> %b%s%b\n" "${color}" "${NC}" "${msg}" "${NC}"
}

error_msg() {
  printf "%bError:%b %s\n" "${RED}" "${NC}" "$1" >&2
}

trap_error() {
  local exit_code=$?
  local failed_command=${BASH_COMMAND}
  local line_number=${BASH_LINENO[0]}
  local func_name=${FUNCNAME[1]:-main}
  error_msg "Command '${failed_command}' failed with exit code ${exit_code}."
  printf "  at %s() line %s\n" "${func_name}" "${line_number}" >&2
  if [[ ${#FUNCNAME[@]} -gt 2 ]]; then
    printf "  Call stack:\n" >&2
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
      printf "    %s() at line %s\n" "${FUNCNAME[i]}" "${BASH_LINENO[i - 1]}" >&2
    done
  fi
  exit "${exit_code}"
}

trap trap_error ERR
# Close redirected fds so tee subprocesses see EOF, then wait for them to flush.
trap 'exec >&- 2>&-; wait' EXIT

setup_logging() {
  LOG_FILE="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S)-$$.log"
  mkdir -p "${LOG_DIR}"
  # Merge stderr into stdout before the tee so a single sed process
  # appends to the log. POSIX guarantees atomic O_APPEND only up to
  # PIPE_BUF (4096 bytes on Linux); separate stdout/stderr appenders
  # would interleave at byte boundaries when verbose nix output emits
  # long single lines (store-path arrays, dumped derivations). The
  # outer tee preserves ANSI on the terminal; sed strips the file copy.
  exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >>"${LOG_FILE}")) 2>&1
  status_msg "${GREEN}" "Logging to: ${LOG_FILE}"
}

announce_path_ref() {
  if [[ -n ${PATH_REF_REASON} ]]; then
    status_msg "${YELLOW}" \
      "Using path:${FLAKE_DIR} (${PATH_REF_REASON}); self.rev is unset there, so system.configurationRevision is dropped and nixos-version --json reports no revision."
    status_msg "${YELLOW}" \
      "path: also dumps the tree unfiltered, so .gitignore'd paths (.direnv/, tmp/, *.log) are copied into the store, and in a primary checkout under --allow-dirty that includes the whole .git directory. Secrets-block matches abort the build instead, in this tree and in submodule working trees alike; see --allow-secret-copy."
  elif [[ ${CACHE_COVERAGE} == "true" ]]; then
    # Not the branch above with a different reason string: the build keeps the
    # bare ref here, so self.rev survives and only the coverage probe copies.
    # cache-coverage.sh hardcodes path: with no --allow-dirty gate, so a clean
    # primary checkout hands it .git as well.
    status_msg "${YELLOW}" \
      "The build keeps the bare ${FLAKE_DIR} ref, so system.configurationRevision is unaffected, but --cache-coverage runs scripts/cache-coverage.sh, which hardcodes path:${FLAKE_DIR}. That copy is unfiltered: .gitignore'd paths and the whole .git directory of a primary checkout reach the store. The same secrets-block abort applies; see --allow-secret-copy."
  fi
}

ensure_no_ignored_secrets() {
  # scripts/cache-coverage.sh hardcodes FLAKE_REF="path:${FLAKE_DIR}" with no
  # bare-ref branch, so --cache-coverage reaches the same unfiltered copy even
  # where resolve_installable chose the bare form and PATH_REF_REASON is empty.
  if [[ -z ${PATH_REF_REASON} && ${CACHE_COVERAGE} != "true" ]]; then
    return 0
  fi
  # An empty PATH_REF_REASON here means the gate above let the run through on
  # CACHE_COVERAGE alone, so resolve_installable returned the bare ref and
  # naming path: would blame a reference this run never uses.
  local copier="path:${FLAKE_DIR}"
  if [[ -z ${PATH_REF_REASON} ]]; then
    copier="scripts/cache-coverage.sh, which --cache-coverage runs against a hardcoded path:${FLAKE_DIR},"
  fi
  local rc=0
  secrets_guard_enforce "${FLAKE_DIR}" "${copier}" || rc=$?
  if [[ ${rc} -eq 2 ]]; then
    printf "Refusing to build with the secrets guard inoperative.\n" >&2
    exit 1
  fi
  if [[ ${rc} -ne 0 ]]; then
    exit 1
  fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  -p | --flake-dir)
    if [[ -z ${2:-} ]]; then
      error_msg "Option $1 requires an argument"
      exit 1
    fi
    FLAKE_DIR="$2"
    shift 2
    ;;
  -t | --host)
    if [[ -z ${2:-} ]]; then
      error_msg "Option $1 requires an argument"
      exit 1
    fi
    TARGET_HOST="$2"
    shift 2
    ;;
  -o | --offline)
    OFFLINE=true
    shift
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  --boot)
    ACTION="boot"
    shift
    ;;
  --allow-dirty)
    ALLOW_DIRTY=true
    shift
    ;;
  --allow-secret-copy)
    ALLOW_SECRET_COPY=true
    shift
    ;;
  --update)
    AUTO_UPDATE=true
    shift
    ;;
  --skip-hooks)
    SKIP_HOOKS=true
    shift
    ;;
  --skip-check)
    SKIP_CHECK=true
    shift
    ;;
  --skip-all)
    SKIP_HOOKS=true
    SKIP_CHECK=true
    SKIP_SCORE=true
    shift
    ;;
  --skip-firmware)
    SKIP_FIRMWARE=true
    shift
    ;;
  --keep-going)
    KEEP_GOING=true
    shift
    ;;
  --repair)
    REPAIR=true
    shift
    ;;
  --fallback)
    FALLBACK=true
    shift
    ;;
  --bootstrap)
    BOOTSTRAP_CACHES=true
    shift
    ;;
  --cache-coverage)
    CACHE_COVERAGE=true
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *)
    error_msg "Unknown option: ${1}"
    show_help
    exit 1
    ;;
  esac
done

# Validate ACTION is a known value
case "${ACTION}" in
switch | boot) ;;
*)
  error_msg "Invalid ACTION: ${ACTION} (must be 'switch' or 'boot')"
  exit 1
  ;;
esac

# Validate configuration directory
if [[ ! -d ${FLAKE_DIR} ]]; then
  error_msg "Configuration directory not found: ${FLAKE_DIR}"
  exit 1
fi

# Absolute from here on. A relative -p argument would reach Lix as
# `path:relative/dir`, and its path fetcher throws
# "cannot fetch input ... because it uses a relative path" when it writes
# flake.lock back.
FLAKE_DIR="$(cd "${FLAKE_DIR}" && pwd -P)"

if [[ ! -f "${FLAKE_DIR}/flake.nix" ]]; then
  error_msg "flake.nix not found in ${FLAKE_DIR}"
  exit 1
fi

# Resolved here, where FLAKE_DIR and ALLOW_DIRTY are final, but announced from
# main() after setup_logging: the notice explains a missing
# system.configurationRevision, so it has to reach the log the reader consults.
# Both reasons cost the same stamp, so this does not track the worktree alone.
if [[ ${ALLOW_DIRTY} == "true" || ${ALLOW_DIRTY} == "1" ]]; then
  PATH_REF_REASON="allow-dirty"
elif [[ -f "${FLAKE_DIR}/.git" ]]; then
  PATH_REF_REASON="linked worktree"
else
  PATH_REF_REASON=""
fi
readonly PATH_REF_REASON

# Configure build settings
# Bootstrap substituters for first builds, before the host substituter
# configuration from modules/hosts/common/nix-substituters.nix is active.
BOOTSTRAP_SUBSTITUTERS=(
  "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
  #"https://mirror.sjtu.edu.cn/nix-channels/store"
  # "https://mirrors.ustc.edu.cn/nix-channels/store"
  "https://cache.nixos.org"
  "https://cache.numtide.com"
  "https://nixpkgs-unfree.cachix.org"
  # CI-built custom derivations (cache-roots); this list replaces rather than
  # extends nix.conf, so omitting it makes a bootstrap build rebuild them.
  "https://bad3r-nixos.cachix.org"
  "https://nix-logseq-git-flake.cachix.org"
  "https://nix-community.cachix.org"
  "https://doom-emacs-unstraightened.cachix.org"
)
BOOTSTRAP_TRUSTED_KEYS=(
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
  "bad3r-nixos.cachix.org-1:CWwJIEV6kogZP/xZPRXdT6hkKvs84haLxYgK9oF59JE="
  "nix-logseq-git-flake.cachix.org-1:DSBNW07PSRyCvS926tpIWahb53OIydwwZhsP6LhJNZo="
  "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  "doom-emacs-unstraightened.cachix.org-1:O5oOlRPnmQEvVaFyuMTmthCEooHbrg54WgSLR07tmg4="
)

configure_build_flags() {
  local build_cores="0" # 0 = all cores per build job
  # Half the cores: a low fixed cap serializes the many small derivations in a
  # system closure behind long compiles, while cores=0 with one job per core
  # lets peak RAM stack with every concurrent source build.
  local build_max_jobs
  build_max_jobs="$((($(nproc) + 1) / 2))"

  BUILD_FLAGS=(
    "--cores" "${build_cores}"
    "--max-jobs" "${build_max_jobs}"
    "--accept-flake-config"
    "--extra-experimental-features" "${BOOTSTRAP_EXPERIMENTAL_FEATURES}"
  )

  # Offline mode
  if [[ ${OFFLINE} == "true" ]]; then
    BUILD_FLAGS+=("--offline")
  fi

  # Verbose mode
  if [[ ${VERBOSE} == "true" ]]; then
    BUILD_FLAGS+=("--verbose")
    set -x
  fi

  # Keep going despite failures
  if [[ ${KEEP_GOING} == "true" ]]; then
    BUILD_FLAGS+=("--keep-going")
  fi

  # Repair corrupted store paths
  if [[ ${REPAIR} == "true" ]]; then
    BUILD_FLAGS+=("--repair")
  fi

  # Fall back to local builds when substituters cannot provide a path
  if [[ ${FALLBACK} == "true" ]]; then
    BUILD_FLAGS+=("--fallback")
  fi
}

configure_nix_config() {
  append_nix_config_line() {
    printf -v NIX_CONFIG '%s%s\n' "${NIX_CONFIG}" "$1"
  }

  NIX_CONFIG=""
  # Bootstrap-only settings for the Nix commands launched by this script.
  # Durable daemon settings live in modules/base/nix-settings.nix.
  append_nix_config_line "experimental-features = ${BOOTSTRAP_EXPERIMENTAL_FEATURES}"
  append_nix_config_line "accept-flake-config = true"
  # IFD required by `nix-doom-emacs-unstraightened` (see flake.nix#nixConfig).
  append_nix_config_line "allow-import-from-derivation = true"
  append_nix_config_line "abort-on-warn = false"

  # Append the token line only when a non-empty token is obtained. An empty
  # value still sends an Authorization header that GitHub rejects with 401,
  # so anonymous access must mean no access-tokens line at all.
  local github_token=""
  if command -v gh >/dev/null 2>&1; then
    github_token="$(gh auth token 2>/dev/null)" || github_token=""
  fi
  if [[ -n ${github_token} ]]; then
    append_nix_config_line "access-tokens = github.com=${github_token}"
  else
    status_msg "${YELLOW}" "No GitHub token from 'gh auth token'; github: inputs fetch anonymously."
  fi

  append_nix_config_line "warn-dirty = false"
  append_nix_config_line "download-attempts = 3"
  append_nix_config_line "stalled-download-timeout = 300"
  append_nix_config_line "max-substitution-jobs = 0"
  append_nix_config_line "http-connections = 0"
  append_nix_config_line "connect-timeout = 30"

  if [[ ${BOOTSTRAP_CACHES} == "true" ]]; then
    append_nix_config_line "substituters = ${BOOTSTRAP_SUBSTITUTERS[*]}"
    append_nix_config_line "trusted-public-keys = ${BOOTSTRAP_TRUSTED_KEYS[*]}"

    append_nix_config_line "http2 = true"
    append_nix_config_line "narinfo-cache-negative-ttl = 60"

  fi

  export NIX_CONFIG
}

resolve_installable() {
  # Two cases need a path: reference rather than the git+file one Lix infers
  # from a bare directory. With allow-dirty, so untracked files reach
  # evaluation at all (git+file ignores them). In a linked worktree, because
  # .git is a file there and Lix reads it as a directory:
  #   error: opening file '<dir>/.git/config': Not a directory
  # Elsewhere the bare form stays, since path: dumps the tree unfiltered:
  # a primary checkout would copy all of .git into the store, and self.rev
  # would go missing along with system.configurationRevision.
  if [[ ${ALLOW_DIRTY} == "true" || ${ALLOW_DIRTY} == "1" || -f "${FLAKE_DIR}/.git" ]]; then
    printf "path:%s" "${FLAKE_DIR}"
  else
    printf "%s" "${FLAKE_DIR}"
  fi
}

ensure_clean_git_tree() {
  # Respect explicit override via flag or env var
  if [[ ${ALLOW_DIRTY} == "true" || ${ALLOW_DIRTY} == "1" ]]; then
    return 0
  fi
  # Scope every git call to FLAKE_DIR: the guard protects the flake being
  # built, not whatever repository the current directory happens to be in.
  if command -v git >/dev/null 2>&1 && git -C "${FLAKE_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Refresh the index and detect any changes (staged, unstaged, untracked)
    git -C "${FLAKE_DIR}" update-index -q --refresh || true
    if ! git -C "${FLAKE_DIR}" diff --quiet --ignore-submodules=dirty -- .; then
      error_msg "Git worktree has unstaged changes. Commit or stash before building."
      git -C "${FLAKE_DIR}" status --porcelain=v1 | sed -n '1,50p' >&2 || true
      printf "Use --allow-dirty or ALLOW_DIRTY=1 to override.\n" >&2
      exit 2
    fi
    if ! git -C "${FLAKE_DIR}" diff --cached --quiet --ignore-submodules=dirty -- .; then
      error_msg "Git index has staged but uncommitted changes. Commit or stash before building."
      git -C "${FLAKE_DIR}" status --porcelain=v1 | sed -n '1,50p' >&2 || true
      printf "Use --allow-dirty or ALLOW_DIRTY=1 to override.\n" >&2
      exit 2
    fi
    # Consider untracked files as dirty to ensure reproducibility
    if [[ -n "$(git -C "${FLAKE_DIR}" ls-files --others --exclude-standard)" ]]; then
      error_msg "Untracked files present in the worktree. Commit, .gitignore, or remove them before building."
      git -C "${FLAKE_DIR}" ls-files --others --exclude-standard | sed -n '1,50p' >&2 || true
      printf "Use --allow-dirty or ALLOW_DIRTY=1 to override.\n" >&2
      exit 2
    fi
  fi
}

sync_pre_commit_hooks() {
  local sync_script="${FLAKE_DIR}/scripts/hooks/sync-pre-commit-hooks.sh"
  if [[ ! -x ${sync_script} ]]; then
    error_msg "Hook sync script not found or not executable: ${sync_script}"
    exit 1
  fi

  status_msg "${YELLOW}" "Synchronizing pre-commit hooks for worktree compatibility..."
  (
    cd "${FLAKE_DIR}"
    nix develop "$(resolve_installable)" "${BUILD_FLAGS[@]}" -c bash "${sync_script}"
  )
}

check_reboot_needed() {
  local booted_system current_system
  booted_system="$(readlink -f /run/booted-system 2>/dev/null || true)"
  current_system="$(readlink -f /run/current-system 2>/dev/null || true)"

  if [[ -z ${booted_system} || -z ${current_system} ]]; then
    status_msg "${YELLOW}" "Unable to resolve /run/booted-system or /run/current-system; skipping reboot check."
    return 0
  fi

  if [[ ${booted_system} != "${current_system}" ]]; then
    printf "\n"
    status_msg "${YELLOW}" "Reboot recommended to apply changes: booted generation differs from current generation."
    printf "    - Booted: %s\n" "${booted_system}"
    printf "    - Current: %s\n" "${current_system}"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send \
        --urgency=normal \
        --app-name="NixOS Build" \
        --icon="${HOME}/.local/share/icons/Ant-Dark/apps/scalable/system-reboot.svg" \
        --category=system \
        "Reboot Recommended" \
        "Booted generation differs from current generation." 2>/dev/null || true
    fi
  fi
}

run_flake_update() {
  local installable
  installable="$(resolve_installable)"
  status_msg "${YELLOW}" "Refreshing flake metadata..."
  nix flake metadata "${installable}" --refresh "${BUILD_FLAGS[@]}"
  status_msg "${YELLOW}" "Updating flake inputs..."
  # The flake goes in --flake: positional arguments here are input names.
  nix flake update --flake "${installable}" "${BUILD_FLAGS[@]}"
}

resolve_nh_command() {
  if command -v nh >/dev/null 2>&1; then
    NH_CMD=(nh)
    return 0
  fi

  if [[ ${OFFLINE} == "true" ]]; then
    error_msg "nh not found in PATH and offline mode is enabled; cannot bootstrap nh."
    exit 1
  fi

  status_msg "${YELLOW}" "nh not found in PATH; bootstrapping via nixpkgs#nh for this run."
  NH_CMD=(nix run nixpkgs#nh --)
}

run_firmware_updates() {
  if ! command -v fwupdmgr >/dev/null 2>&1; then
    status_msg "${YELLOW}" "fwupdmgr not found; skipping firmware updates."
    status_msg "${YELLOW}" "Install/enable fwupd tooling to manage LVFS firmware updates on switch."
    return 0
  fi

  status_msg "${YELLOW}" "Checking/applying firmware updates via fwupdmgr..."
  local firmware_failed=false

  if ! /run/wrappers/bin/sudo fwupdmgr refresh --force; then
    firmware_failed=true
    status_msg "${YELLOW}" "Firmware metadata refresh failed (manual retry: sudo fwupdmgr refresh --force)."
  fi

  if ! /run/wrappers/bin/sudo fwupdmgr get-updates; then
    firmware_failed=true
    status_msg "${YELLOW}" "Firmware update query failed (manual retry: sudo fwupdmgr get-updates)."
  fi

  if ! /run/wrappers/bin/sudo fwupdmgr update; then
    firmware_failed=true
    status_msg "${YELLOW}" "Firmware update apply step reported an error (manual retry: sudo fwupdmgr update)."
  fi

  if [[ ${firmware_failed} == "true" ]]; then
    status_msg "${YELLOW}" "Firmware update step completed with warnings; system switch remains successful."
  else
    status_msg "${GREEN}" "Firmware update step completed."
  fi
}

main() {
  setup_logging
  announce_path_ref
  # Outside the AUTO_UPDATE branch below, unlike ensure_clean_git_tree: an
  # update run reaches the same store copy through the same path: ref.
  ensure_no_ignored_secrets
  configure_nix_config
  configure_build_flags

  if [[ ${AUTO_UPDATE} == "true" ]]; then
    run_flake_update
  else
    # Fail fast on dirty git trees to ensure reproducible builds
    ensure_clean_git_tree
  fi

  if [[ ${SKIP_HOOKS} == "false" ]]; then
    sync_pre_commit_hooks
    status_msg "${YELLOW}" "Running pre-commit hooks..."
    (
      cd "${FLAKE_DIR}"
      nix develop "$(resolve_installable)" "${BUILD_FLAGS[@]}" -c pre-commit run --all-files --hook-stage manual
    )
  else
    status_msg "${YELLOW}" "Skipping pre-commit hooks (--skip-hooks flag used)..."
  fi

  if [[ ${SKIP_SCORE} == "false" ]]; then
    if command -v generation-manager >/dev/null 2>&1; then
      status_msg "${YELLOW}" "Scoring Dendritic Pattern compliance..."
      generation-manager score
    else
      status_msg "${YELLOW}" "Skipping Dendritic Pattern scoring (generation-manager not found)..."
    fi
  else
    status_msg "${YELLOW}" "Skipping Dendritic Pattern scoring (--skip-all flag used)..."
  fi

  if [[ ${SKIP_CHECK} == "false" ]]; then
    status_msg "${YELLOW}" "Validating flake (evaluation + invariants)..."
    nix flake check "$(resolve_installable)" --no-build "${BUILD_FLAGS[@]}"
  else
    status_msg "${YELLOW}" "Skipping flake check (--skip-check flag used)..."
  fi

  if [[ ${CACHE_COVERAGE} == "true" ]]; then
    status_msg "${YELLOW}" "Checking cache coverage for '${TARGET_HOST}' (narinfo probes, no builds)..."
    # cache-coverage.sh runs the guard unconditionally, so the override has to
    # travel with it. ALLOW_SECRET_COPY is not exported: the environment
    # spelling is inherited, the flag spelling would not be, and the two
    # documented forms of one override would abort differently here.
    local -a coverage_args=(--flake-dir "${FLAKE_DIR}" --host "${TARGET_HOST}")
    if [[ ${ALLOW_SECRET_COPY} == "true" || ${ALLOW_SECRET_COPY} == "1" ]]; then
      coverage_args+=(--allow-secret-copy)
    fi
    "${FLAKE_DIR}/scripts/cache-coverage.sh" "${coverage_args[@]}"
  fi

  status_msg "${GREEN}" "Validation completed successfully!"

  resolve_nh_command

  # Deploy using nh os which handles build + activation with native elevation
  status_msg "${YELLOW}" "Deploying '${TARGET_HOST}' via nh os (${ACTION})..."
  local installable
  installable="$(resolve_installable)"
  case "${ACTION}" in
  switch | boot)
    nh_os_args=(
      os
      "${ACTION}"
      -H "${TARGET_HOST}"
      "${installable}"
    )
    if [[ ${#BUILD_FLAGS[@]} -gt 0 ]]; then
      nh_os_args+=(-- "${BUILD_FLAGS[@]}")
    fi
    "${NH_CMD[@]}" "${nh_os_args[@]}"
    if [[ ${ACTION} == "switch" ]]; then
      status_msg "${GREEN}" "System switched successfully!"
      if [[ ${SKIP_FIRMWARE} == "false" ]]; then
        run_firmware_updates
      else
        status_msg "${YELLOW}" "Skipping firmware updates (--skip-firmware flag used)..."
      fi
      check_reboot_needed
    else
      status_msg "${GREEN}" "Generation installed. It will become active on next reboot."
    fi
    ;;
  *)
    error_msg "Unknown ACTION: ${ACTION}"
    exit 1
    ;;
  esac
}

main
