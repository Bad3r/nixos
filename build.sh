#!/usr/bin/env bash
# Common Usage:
# ./build.sh --collect-garbage --optimize --offline
set -eo pipefail

# Enable Nix experimental features
export NIX_CONFIG="
accept-flake-config = true
abort-on-warn = true
allow-import-from-derivation = true
experimental-features = nix-command flakes pipe-operators
"

# Initialize variables with defaults
FLAKE_DIR="${PWD}"
HOSTNAME="$(hostname)"
OFFLINE=false
VERBOSE=false
OPTIMIZE_STORE=false
GARBAGE_COLLECT=false
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
  -d, --collect-garbage  Run 'nix-collect-garbage -d' after build
  -O, --optimize         Optimize Nix store after build
  -h, --help             Show this help message

  Usage Example:
  $0 --collect-garbage --optimize --offline
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
  -O | --optimize)
    OPTIMIZE_STORE=true
    shift
    ;;
  -d | --collect-garbage)
    GARBAGE_COLLECT=true
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
    "--option" "sandbox" "false"
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

# Build result caching
optimize_store() {
  status_msg "${YELLOW}" "Optimizing Nix store..."
  nix-store --optimise
}

collect_garbage() {
  status_msg "${YELLOW}" "Running garbage collection..."
  nix-collect-garbage -d
  nix-collect-garbage -d
}

main() {
  bash -c "cd \"${FLAKE_DIR}\" && git add ."

  configure_nix_flags

  status_msg "${YELLOW}" "Formatting Nix files..."
  nix fmt "${FLAKE_DIR}"

  status_msg "${YELLOW}" "Validating flake configuration..."
  nix flake check "${FLAKE_DIR}" --accept-flake-config || {
    error_msg "Flake validation failed"
    exit 1
  }

  # Skip updates in offline mode
  if ! $OFFLINE; then
    status_msg "${YELLOW}" "Updating all flake inputs..."
    nix flake update "${FLAKE_DIR}" "${NIX_FLAGS[@]}"
  else
    status_msg "${YELLOW}" "Skipping flake updates (offline mode)"
  fi

  status_msg "${YELLOW}" "Building system configuration for ${HOSTNAME}..."
  CMD=(nixos-rebuild switch
    --flake "${FLAKE_DIR}#${HOSTNAME}"
    "${NIX_FLAGS[@]}"
  )
  "${CMD[@]}"

  if $GARBAGE_COLLECT; then
    collect_garbage
  fi

  if $OPTIMIZE_STORE; then
    optimize_store
  fi

  sudo chown -R vx: "$PWD"/.git && git add -A
  status_msg "${GREEN}" "Build completed successfully!"
}

trap 'error_msg "Build failed!"; exit 1' ERR
main
