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
set -eo pipefail

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
ALLOW_DIRTY=false
ACTION="switch" # default action after build: switch | boot
NIX_FLAGS=()
SUBMODULES=(inputs/home-manager inputs/nixpkgs inputs/stylix)

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
  --boot)
    ACTION="boot"
    shift
    ;;
  --allow-dirty)
    ALLOW_DIRTY=true
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

ensure_clean_git_tree() {
  # Respect explicit override via flag or env var
  if ${ALLOW_DIRTY} || [[ ${ALLOW_DIRTY:-} == "1" ]]; then
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

main() {
  # Fail fast on dirty git trees to ensure reproducible builds
  ensure_clean_git_tree

  # Ensure required input branches and submodules are present
  status_msg "${YELLOW}" "Ensuring inputs/* submodules are initialized..."
  if command -v git >/dev/null 2>&1; then
    # Fetch input branches into the superproject so local submodule clones (url=./.) can see them
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      need_init=0
      for sub in "${SUBMODULES[@]}"; do
        if [[ ! -e "$sub/.git" || ! -f "$sub/flake.nix" ]]; then
          need_init=1
          break
        fi
      done

      if [[ $need_init -eq 1 ]]; then
        git submodule sync --recursive || true
        # Try shallow init directly from the repo origin, not via superproject refs.
        if ! git submodule update --init --recursive --depth 1; then
          status_msg "${YELLOW}" "Submodule clone with relative URL failed. Retrying via origin remote..."
          PARENT_ORIGIN=$(git remote get-url --push origin 2>/dev/null || git remote get-url origin 2>/dev/null || true)
          if [[ -z ${PARENT_ORIGIN} ]]; then
            error_msg "Could not resolve superproject origin URL for submodule initialization."
            exit 1
          fi
          for name in home-manager nixpkgs stylix; do
            git config "submodule.inputs/${name}.url" "${PARENT_ORIGIN}" || true
          done
          # Avoid protocol.file fallback; rely on network origin instead
          if ! git submodule update --init --recursive --depth 1; then
            error_msg "Submodule init failed from origin. See docs/INPUT-BRANCHES-PLAN.md."
            exit 1
          fi
        fi
        # Ensure nixpkgs submodule stays blobless for follow-up operations
        if [[ -d inputs/nixpkgs ]]; then
          git -C inputs/nixpkgs config remote.origin.promisor true || true
          git -C inputs/nixpkgs config remote.origin.partialclonefilter blob:none || true
        fi
      fi
    fi
  fi

  # Verify submodules look sane before invoking nix
  for sub in inputs/home-manager inputs/nixpkgs inputs/stylix; do
    if [[ -d $sub ]]; then
      # In submodules, .git is often a FILE pointing to ../.git/modules/... not a directory
      if [[ ! -d "$sub/.git" && ! -f "$sub/.git" ]]; then
        error_msg "Submodule '$sub' not initialized. Run: git fetch origin 'refs/heads/inputs/*:refs/heads/inputs/*' && git submodule sync --recursive && git submodule update --init --recursive"
        exit 1
      fi
      if [[ ! -f "$sub/flake.nix" ]]; then
        error_msg "Missing flake.nix in '$sub'. Ensure input branches are populated (see docs/INPUT-BRANCHES-PLAN.md)."
        exit 1
      fi
    fi
  done

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
    /run/wrappers/bin/sudo --preserve-env=NIX_CONFIG,NIX_CONFIGURATION nixos-rebuild "${ACTION}" --flake "${FLAKE_DIR}#${HOSTNAME}" --accept-flake-config "${NIX_FLAGS[@]}"
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

trap 'error_msg "Build failed!"; exit 1' ERR
main
