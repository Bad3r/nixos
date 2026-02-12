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

# Nix CLI config via env: enable nix-command, flakes, pipe-operators, etc.
# Keep aligned with flake.nix nixConfig; do not relax security settings.
NIX_CONFIGURATION=$'experimental-features = nix-command flakes pipe-operators\n'
NIX_CONFIGURATION+=$'accept-flake-config = true\n'
NIX_CONFIGURATION+=$'allow-import-from-derivation = false\n'
NIX_CONFIGURATION+=$'abort-on-warn = false\n'
# Authenticate with GitHub to avoid API rate limits during flake operations
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  NIX_CONFIGURATION+="access-tokens = github.com=$(gh auth token)"$'\n'
fi
# Note: Avoid restricted settings that cause warnings for non-trusted users
# (e.g., substituters, trusted-public-keys, log-lines). Those should be
# configured system-wide via nix.settings for trusted users.
export NIX_CONFIGURATION

# Back-compat for Nix versions that read NIX_CONFIG only
export NIX_CONFIG="${NIX_CONFIGURATION}"

# Above export mirrors flake-provided nixConfig and required features.

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
NIX_FLAGS=()
NH_FLAGS=()
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
      --update           Run 'nix flake update' and auto-commit before building
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

# When explicitly allowing dirty trees, suppress Nix's dirty tree warning.
if [[ ${ALLOW_DIRTY} == "true" || ${ALLOW_DIRTY} == "1" ]]; then
  NIX_CONFIGURATION+=$'warn-dirty = false\n'
  export NIX_CONFIGURATION
  export NIX_CONFIG="${NIX_CONFIGURATION}"
fi

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
  local nix_flags=()
  local nh_flags=()

  nix_flags+=(
    "--option" "cores" "3"
    "--option" "max-jobs" "2"
  )
  nh_flags+=(
    "--cores" "3"
    "--max-jobs" "2"
    "--accept-flake-config"
  )

  # Offline mode
  if [[ ${OFFLINE} == "true" ]]; then
    nix_flags+=("--offline")
    nh_flags+=("--offline")
  fi

  # Verbose mode
  if [[ ${VERBOSE} == "true" ]]; then
    nix_flags+=("--verbose")
    nh_flags+=("--verbose")
    set -x
  fi

  # Keep going despite failures
  if [[ ${KEEP_GOING} == "true" ]]; then
    nix_flags+=("--keep-going")
    nh_flags+=("--keep-going")
  fi

  # Repair corrupted store paths
  if [[ ${REPAIR} == "true" ]]; then
    nix_flags+=("--repair")
    nh_flags+=("--repair")
  fi

  # Bootstrap caches for first build (replaces system substituters entirely)
  if [[ ${BOOTSTRAP_CACHES} == "true" ]]; then
    # Apply bootstrap cache configuration via environment so it is honored by
    # both direct `nix` commands and `nh`-driven builds.
    NIX_CONFIGURATION+="substituters = ${BOOTSTRAP_SUBSTITUTERS[*]}"$'\n'
    NIX_CONFIGURATION+="trusted-public-keys = ${BOOTSTRAP_TRUSTED_KEYS[*]}"$'\n'
    export NIX_CONFIGURATION
    export NIX_CONFIG="${NIX_CONFIGURATION}"
  fi

  NIX_FLAGS=("${nix_flags[@]}")
  NH_FLAGS=("${nh_flags[@]}")
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

check_reboot_needed() {
  local needs_reboot=false
  local reasons=()

  # Check kernel version
  local running_kernel current_kernel current_kernel_link
  running_kernel="$(uname -r)"
  # Extract version number from kernel path.
  # Handles standard kernels (linux-6.19), patch versions (linux-6.18.9),
  # and CachyOS variants (linux-cachyos-...-6.18.8) without tripping pipefail.
  current_kernel_link="$(readlink /run/current-system/kernel 2>/dev/null || true)"
  current_kernel="$(printf '%s\n' "${current_kernel_link}" | sed -nE 's#.*-linux[^/]*-([0-9]+\.[0-9]+(\.[0-9]+)?)([^0-9].*)?$#\1#p')"

  if [[ -n ${current_kernel} ]]; then
    if [[ ${running_kernel} != "${current_kernel}" ]]; then
      needs_reboot=true
      reasons+=("Kernel: ${running_kernel} -> ${current_kernel}")
    fi
  else
    status_msg "${YELLOW}" "Unable to parse target kernel version from /run/current-system/kernel (${current_kernel_link:-unavailable}); skipping kernel reboot check."
  fi

  # Check nvidia driver (if present)
  if [[ -d /run/current-system/sw/lib/nvidia ]]; then
    local running_nvidia current_nvidia
    running_nvidia="$(cat /sys/module/nvidia/version 2>/dev/null || echo "not loaded")"
    current_nvidia="$(readlink /run/current-system/sw/lib/nvidia | sed 's/.*nvidia-//;s/-.*$//' || echo "unknown")"
    if [[ ${running_nvidia} != "${current_nvidia}" && ${running_nvidia} != "not loaded" ]]; then
      needs_reboot=true
      reasons+=("NVIDIA: ${running_nvidia} -> ${current_nvidia}")
    fi
  fi

  if [[ ${needs_reboot} == "true" ]]; then
    printf "\n"
    status_msg "${YELLOW}" "Reboot recommended to apply changes:"
    local body=""
    for reason in "${reasons[@]}"; do
      printf "    - %s\n" "${reason}"
      body+="${reason}"$'\n'
    done
    # Desktop notification (non-blocking, don't fail if unavailable)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send \
        --urgency=normal \
        --app-name="NixOS Build" \
        --icon="${HOME}/.local/share/icons/Ant-Dark/apps/scalable/system-reboot.svg" \
        --category=system \
        "Reboot Recommended" \
        "$(printf "%b" "${body}")" 2>/dev/null || true
    fi
  fi
}

run_flake_update() {
  status_msg "${YELLOW}" "Refreshing flake metadata..."
  nix flake metadata "${FLAKE_DIR}" --refresh "${NIX_FLAGS[@]}"
  status_msg "${YELLOW}" "Updating flake inputs..."
  nix flake update --flake "${FLAKE_DIR}" "${NIX_FLAGS[@]}"
  if command -v git >/dev/null 2>&1; then
    if git -C "${FLAKE_DIR}" diff --quiet -- flake.lock; then
      status_msg "${GREEN}" "flake.lock already up to date."
    else
      status_msg "${YELLOW}" "Committing flake.lock changes..."
      git -C "${FLAKE_DIR}" add flake.lock
      git -C "${FLAKE_DIR}" commit -m "chore(flake): update inputs"
    fi
  fi
}

check_sudo_access() {
  if ! /run/wrappers/bin/sudo -n true 2>/dev/null; then
    status_msg "${YELLOW}" "Sudo access required for firmware updates. You may be prompted for your password."
    if ! /run/wrappers/bin/sudo -v; then
      error_msg "Failed to obtain sudo access. Cannot proceed with firmware updates."
      exit 1
    fi
  fi
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
  NH_CMD=(nix run --accept-flake-config nixpkgs#nh --)
}

run_firmware_updates() {
  if ! command -v fwupdmgr >/dev/null 2>&1; then
    status_msg "${YELLOW}" "fwupdmgr not found; skipping firmware updates."
    status_msg "${YELLOW}" "Install/enable fwupd tooling to manage LVFS firmware updates on switch."
    return 0
  fi

  check_sudo_access

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
  if [[ ${AUTO_UPDATE} == "true" ]]; then
    run_flake_update
  fi

  # Fail fast on dirty git trees to ensure reproducible builds
  ensure_clean_git_tree

  configure_build_flags

  if [[ ${SKIP_HOOKS} == "false" ]]; then
    status_msg "${YELLOW}" "Running pre-commit hooks..."
    nix develop --accept-flake-config "${NIX_FLAGS[@]}" -c pre-commit run --all-files --hook-stage manual
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
    nix flake check "${FLAKE_DIR}" --accept-flake-config --no-build "${NIX_FLAGS[@]}"
  else
    status_msg "${YELLOW}" "Skipping flake check (--skip-check flag used)..."
  fi

  status_msg "${GREEN}" "Validation completed successfully!"

  resolve_nh_command

  # Deploy using nh os which handles build + activation with native elevation
  status_msg "${YELLOW}" "Deploying '${TARGET_HOST}' via nh os (${ACTION})..."
  case "${ACTION}" in
  switch | boot)
    "${NH_CMD[@]}" os "${ACTION}" "${NH_FLAGS[@]}" -H "${TARGET_HOST}" "${FLAKE_DIR}"
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
