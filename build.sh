#!/usr/bin/env bash
# Validation and build helper for this flake
# Common Usage:
#   ./build.sh [--offline] [--verbose] [--auto-switch]
#
# This script performs validation (format, hooks, pattern score, flake checks),
# then builds the system closure as the current user. It will prompt to switch
# (sudo) interactively unless --auto-switch is provided. It never disables the
# sandbox or performs GC/optimise, and it does not mutate repo file ownership.
# Keep permission and state management declarative in NixOS modules.
set -eo pipefail

# Respect flake-provided nixConfig; avoid overriding via NIX_CONFIG here.

# Initialize variables with defaults
FLAKE_DIR="${PWD}"
HOSTNAME="$(hostname)"
OFFLINE=false
VERBOSE=false
NIX_FLAGS=()
AUTO_SWITCH=false

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
  --auto-switch          Switch non-interactively after a successful build
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
  --auto-switch)
    AUTO_SWITCH=true
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

main() {
  configure_nix_flags

  status_msg "${YELLOW}" "Formatting Nix files..."
  nix fmt "${FLAKE_DIR}"

  status_msg "${YELLOW}" "Running pre-commit hooks..."
  nix develop "${NIX_FLAGS[@]}" -c pre-commit run --all-files

  status_msg "${YELLOW}" "Scoring Dendritic Pattern compliance..."
  generation-manager score

  status_msg "${YELLOW}" "Validating flake (evaluation + invariants)..."
  nix flake check "${FLAKE_DIR}" --accept-flake-config --no-build "${NIX_FLAGS[@]}"

  status_msg "${GREEN}" "Validation completed successfully!"

  status_msg "${YELLOW}" "Building system closure for ${HOSTNAME}..."
  local SYSTEM_PATH
  if ! SYSTEM_PATH=$(nix build "${FLAKE_DIR}#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel" --no-link --print-out-paths "${NIX_FLAGS[@]}"); then
    error_msg "Build failed for host '${HOSTNAME}'."
    exit 1
  fi
  printf "Built system closure: %s\n" "$SYSTEM_PATH"

  # Switch step (requires sudo wrapper; when using sudo-rs, the wrapper is 'sudo')
  if $AUTO_SWITCH; then
    status_msg "${YELLOW}" "Auto-switching to new configuration (sudo -n; requires cached creds or NOPASSWD)..."
    if /run/wrappers/bin/sudo -n "${SYSTEM_PATH}/bin/switch-to-configuration" switch; then
      status_msg "${GREEN}" "System switched successfully!"
    else
      error_msg "Non-interactive switch failed. Ensure 'sudo -v' or a NOPASSWD rule, or rerun without --auto-switch."
      exit 1
    fi
  else
    status_msg "${YELLOW}" "Switching to new configuration (sudo may prompt)..."
    /run/wrappers/bin/sudo "${SYSTEM_PATH}/bin/switch-to-configuration" switch
    status_msg "${GREEN}" "System switched successfully!"
  fi
}

trap 'error_msg "Build failed!"; exit 1' ERR
main
