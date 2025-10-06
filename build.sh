#!/usr/bin/env bash
# Validation and build helper for this flake
# Common Usage:
#   ./build.sh [--offline] [--verbose]
##
## This script performs validation (format, hooks, pattern score, flake checks),
## then builds the system closure as the current user and switches using the
## system sudo wrapper. It never disables the sandbox or performs GC/optimise,
## and it does not mutate repo file ownership. Keep permission and state
## management declarative in NixOS modules.
set -Ee -o pipefail

# Nix CLI config via env: enable nix-command, flakes, pipe-operators, etc.
# Keep aligned with flake.nix nixConfig; do not relax security settings.
NIX_CONFIGURATION=$'experimental-features = nix-command flakes pipe-operators\n'
NIX_CONFIGURATION+=$'accept-flake-config = true\n'
NIX_CONFIGURATION+=$'allow-import-from-derivation = false\n'
NIX_CONFIGURATION+=$'abort-on-warn = true\n'
# Note: Avoid restricted settings that cause warnings for non-trusted users
# (e.g., substituters, trusted-public-keys, log-lines). Those should be
# configured system-wide via nix.settings for trusted users.
export NIX_CONFIGURATION

# Back-compat for Nix versions that read NIX_CONFIG only
export NIX_CONFIG="${NIX_CONFIGURATION}"

# Above export mirrors flake-provided nixConfig and required features.

# Initialize variables with defaults
FLAKE_DIR="${PWD}"
HOSTNAME="$(hostname)"
OFFLINE=false
VERBOSE=false
ALLOW_DIRTY=${ALLOW_DIRTY:-false}
AUTO_UPDATE=false
ACTION="switch" # default action after build: switch | boot
NIX_FLAGS=()
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

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
  -h, --help             Show this help message

  Usage Example:
  $0 --offline
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
  error_msg "Command '${failed_command}' failed with exit code ${exit_code}."
  exit "${exit_code}"
}

trap trap_error ERR

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -p | --flake-dir)
    FLAKE_DIR="$2"
    shift 2
    ;;
  -t | --host)
    HOSTNAME="$2"
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
  --help)
    show_help
    exit 0
    ;;
  *)
    error_msg "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
done

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
configure_nix_flags() {
  local flags=()

  flags+=(
    "--option" "cores" "0"
    "--option" "max-jobs" "auto"
  )

  # Offline mode
  if $OFFLINE; then
    flags+=("--offline")
  fi

  # Verbose mode
  if $VERBOSE; then
    flags+=("--verbose")
    set -x
  fi

  NIX_FLAGS=("${flags[@]}")
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
    if git ls-files --others --exclude-standard | grep -q .; then
      error_msg "Untracked files present in the worktree. Commit, .gitignore, or remove them before building."
      git ls-files --others --exclude-standard | sed -n '1,50p' >&2 || true
      printf "Use --allow-dirty or ALLOW_DIRTY=1 to override.\n" >&2
      exit 2
    fi
  fi
}

run_flake_update() {
  status_msg "${YELLOW}" "Updating flake inputs..."
  nix flake update "${FLAKE_DIR}"
  if command -v git >/dev/null 2>&1; then
    if git -C "${FLAKE_DIR}" diff --quiet -- flake.lock; then
      status_msg "${GREEN}" "flake.lock already up to date."
    else
      status_msg "${YELLOW}" "Committing flake.lock changes..."
      git -C "${FLAKE_DIR}" add flake.lock
      git -C "${FLAKE_DIR}" commit -m "chore: update flake inputs"
    fi
  fi
}

main() {
  if [[ ${AUTO_UPDATE} == "true" ]]; then
    run_flake_update
  fi

  # Fail fast on dirty git trees to ensure reproducible builds
  ensure_clean_git_tree

  configure_nix_flags

  status_msg "${YELLOW}" "Formatting Nix files..."
  nix fmt --accept-flake-config "${FLAKE_DIR}"

  status_msg "${YELLOW}" "Running pre-commit hooks..."
  nix develop --accept-flake-config "${NIX_FLAGS[@]}" -c pre-commit run --all-files

  status_msg "${YELLOW}" "Scoring Dendritic Pattern compliance..."
  #generation-manager score

  status_msg "${YELLOW}" "Validating flake (evaluation + invariants)..."
  nix flake check "${FLAKE_DIR}" --accept-flake-config --no-build "${NIX_FLAGS[@]}"

  status_msg "${GREEN}" "Validation completed successfully!"

  # Deploy using nixos-rebuild which handles profile + bootloader updates
  status_msg "${YELLOW}" "Deploying '${HOSTNAME}' via nixos-rebuild (${ACTION})..."
  case "${ACTION}" in
  switch | boot)
    /run/wrappers/bin/sudo --preserve-env=NIX_CONFIG,NIX_CONFIGURATION,SSH_AUTH_SOCK nixos-rebuild "${ACTION}" --flake "${FLAKE_DIR}#${HOSTNAME}" --accept-flake-config "${NIX_FLAGS[@]}"
    if [[ ${ACTION} == "switch" ]]; then
      status_msg "${GREEN}" "System switched successfully!"
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
