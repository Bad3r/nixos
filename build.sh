#!/usr/bin/env bash
# Validation and build helper for this flake
# Common Usage:
#   ./build.sh [--offline] [--verbose]
##
## This script performs validation (git hooks and flake checks),
## then deploys via `nh os` after validation succeeds. It never disables the
## sandbox or performs GC/optimise,
## and it does not mutate repo file ownership. Keep permission and state
## management declarative in NixOS modules.
set -Eeu -o pipefail

# Initialize variables with defaults
FLAKE_DIR="${PWD}"
TARGET_HOST="$(hostname)"
OFFLINE=false
VERBOSE=false
ALLOW_DIRTY=${ALLOW_DIRTY:-false}
AUTO_UPDATE=false
SKIP_HOOKS=false
SKIP_CHECK=false
SKIP_SCORE=false
SKIP_FIRMWARE=false
KEEP_GOING=false
REPAIR=false
BOOTSTRAP_CACHES=false
ACTION="switch" # default action after build: switch | boot
BUILD_FLAGS=()
NH_CMD=()
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
      --update           Run 'nix flake metadata --refresh' and 'nix flake update' before building
      --skip-hooks       Skip the pre-commit validation
      --skip-check       Skip the 'nix flake check' validation step
      --skip-all         Skip all validation steps (pre-commit hooks, flake check)
      --skip-firmware    Skip firmware refresh/check/apply after successful switch
      --keep-going       Continue building despite failures
      --repair           Repair corrupted store paths during build
      --bootstrap        Use extra substituters for first build (e.g., Determinate Nix)
  -h, --help             Show this help message

  Usage Example:
  ${0} --offline
" "${0##*/}" "${PWD}" "$(hostname)"
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
trap 'true' EXIT # Cleanup hook (no-op; extend as needed)

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
  --bootstrap)
    BOOTSTRAP_CACHES=true
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

if [[ ! -f "${FLAKE_DIR}/flake.nix" ]]; then
  error_msg "flake.nix not found in ${FLAKE_DIR}"
  exit 1
fi

# Configure build settings
# Bootstrap substituters for first build (before system has them configured)
# Used for initial Determinate Nix setup or similar migrations
BOOTSTRAP_SUBSTITUTERS=(
  "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
  "https://mirror.sjtu.edu.cn/nix-channels/store"
  "https://mirrors.ustc.edu.cn/nix-channels/store"
  "https://cache.nixos.org"
  "https://cache.garnix.io"
  "https://cache.numtide.com"
  "https://nixpkgs-unfree.cachix.org"
)
BOOTSTRAP_TRUSTED_KEYS=(
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
)

configure_build_flags() {
  local build_cores="$(($(nproc --all) - 1))" # Nix default = 0 (all cores per build job)
  local build_max_jobs="1"                    # Nix default = 1

  BUILD_FLAGS=(
    "--cores" "${build_cores}"
    "--max-jobs" "${build_max_jobs}"
    "--accept-flake-config"
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
}

configure_nix_config() {
  NIX_CONFIG=$'experimental-features = nix-command flakes pipe-operators\n'
  NIX_CONFIG+=$'accept-flake-config = true\n'
  NIX_CONFIG+=$'allow-import-from-derivation = false\n'
  NIX_CONFIG+=$'abort-on-warn = false\n'

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    NIX_CONFIG+="access-tokens = github.com=$(gh auth token)"$'\n'
  fi

  if [[ ${ALLOW_DIRTY} == "true" || ${ALLOW_DIRTY} == "1" ]]; then
    NIX_CONFIG+=$'warn-dirty = false\n'
  fi

  # Bootstrap caches for first build (replaces system substituters entirely)
  if [[ ${BOOTSTRAP_CACHES} == "true" ]]; then
    NIX_CONFIG+="substituters = ${BOOTSTRAP_SUBSTITUTERS[*]}"$'\n'
    NIX_CONFIG+="trusted-public-keys = ${BOOTSTRAP_TRUSTED_KEYS[*]}"$'\n'
  fi

  export NIX_CONFIG
}

ensure_clean_git_tree() {
  # Respect explicit override via flag or env var
  if [[ ${ALLOW_DIRTY} == "true" || ${ALLOW_DIRTY} == "1" ]]; then
    return 0
  fi
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Refresh the index and detect any changes (staged, unstaged, untracked)
    git update-index -q --refresh || true
    if ! git diff --quiet --ignore-submodules=dirty -- .; then
      error_msg "Git worktree has unstaged changes. Commit or stash before building."
      git status --porcelain=v1 | sed -n '1,50p' >&2 || true
      printf "Use --allow-dirty or ALLOW_DIRTY=1 to override.\n" >&2
      exit 2
    fi
    if ! git diff --cached --quiet --ignore-submodules=dirty -- .; then
      error_msg "Git index has staged but uncommitted changes. Commit or stash before building."
      git status --porcelain=v1 | sed -n '1,50p' >&2 || true
      printf "Use --allow-dirty or ALLOW_DIRTY=1 to override.\n" >&2
      exit 2
    fi
    # Consider untracked files as dirty to ensure reproducibility
    if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
      error_msg "Untracked files present in the worktree. Commit, .gitignore, or remove them before building."
      git ls-files --others --exclude-standard | sed -n '1,50p' >&2 || true
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
    nix develop "${BUILD_FLAGS[@]}" -c bash "${sync_script}"
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
  status_msg "${YELLOW}" "Refreshing flake metadata..."
  nix flake metadata "${FLAKE_DIR}" --refresh "${BUILD_FLAGS[@]}"
  status_msg "${YELLOW}" "Updating flake inputs..."
  nix flake update --flake "${FLAKE_DIR}" "${BUILD_FLAGS[@]}"
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
      nix develop "${BUILD_FLAGS[@]}" -c pre-commit run --all-files --hook-stage manual
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
    nix flake check "${FLAKE_DIR}" --no-build "${BUILD_FLAGS[@]}"
  else
    status_msg "${YELLOW}" "Skipping flake check (--skip-check flag used)..."
  fi

  status_msg "${GREEN}" "Validation completed successfully!"

  resolve_nh_command

  # Deploy using nh os which handles build + activation with native elevation
  status_msg "${YELLOW}" "Deploying '${TARGET_HOST}' via nh os (${ACTION})..."
  case "${ACTION}" in
  switch | boot)
    "${NH_CMD[@]}" os "${ACTION}" "${BUILD_FLAGS[@]}" -H "${TARGET_HOST}" "${FLAKE_DIR}"
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
