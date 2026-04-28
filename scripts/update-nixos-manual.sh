#!/usr/bin/env bash
# shellcheck shell=bash
# update-nixos-manual.sh
# Downloads the NixOS manual markdown sources from the flake's nixpkgs input
# Usage: ./scripts/update-nixos-manual.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MANUAL_DIR="$REPO_ROOT/nixos-manual"
TMP_PARENT=""
STAGED_MANUAL=""
BACKUP_MANUAL=""
updated=false

cleanup() {
  local rc=$?

  if [[ $updated == false && -n $BACKUP_MANUAL && -d $BACKUP_MANUAL && ! -e $MANUAL_DIR ]]; then
    echo "Restoring previous nixos-manual after failed update..." >&2
    mv "$BACKUP_MANUAL" "$MANUAL_DIR"
  fi

  if [[ -n $STAGED_MANUAL && -d $STAGED_MANUAL ]]; then
    rip "$STAGED_MANUAL" >/dev/null 2>&1 || true
  fi

  if [[ -n $TMP_PARENT && -d $TMP_PARENT ]]; then
    rmdir "$TMP_PARENT" 2>/dev/null || true
  fi

  return "$rc"
}

trap cleanup EXIT

nixpkgs_input_attr() {
  local attr="$1"

  REPO_ROOT="$REPO_ROOT" nix eval --raw --impure --expr \
    "(builtins.getFlake \"path:\${builtins.getEnv \"REPO_ROOT\"}\").inputs.nixpkgs.${attr}"
}

cd "$REPO_ROOT"

if ! command -v rip >/dev/null 2>&1; then
  echo "rip is required so old manual copies are removed recoverably." >&2
  exit 1
fi

echo "📥 Fetching nixpkgs path from flake input..."
NIXPKGS_PATH="$(nixpkgs_input_attr outPath)"
NIXPKGS_REV="$(nixpkgs_input_attr rev)"
NIXPKGS_REV_SHORT="${NIXPKGS_REV:0:7}"
MANUAL_SOURCE="$NIXPKGS_PATH/nixos/doc/manual"

echo "   nixpkgs revision: $NIXPKGS_REV_SHORT"

if [[ ! -d $MANUAL_SOURCE ]]; then
  echo "NixOS manual source does not exist: $MANUAL_SOURCE" >&2
  exit 1
fi

TMP_PARENT="$(mktemp -d "$REPO_ROOT/.nixos-manual-update.XXXXXXXX")"
STAGED_MANUAL="$TMP_PARENT/nixos-manual.new"
BACKUP_MANUAL="$TMP_PARENT/nixos-manual.previous"

echo "📋 Staging manual from nixpkgs..."
cp -R "$MANUAL_SOURCE" "$STAGED_MANUAL"
chmod -R u+rwX,go+rX "$STAGED_MANUAL"

echo "🔁 Replacing nixos-manual..."
if [[ -e $MANUAL_DIR ]]; then
  mv "$MANUAL_DIR" "$BACKUP_MANUAL"
fi
mv "$STAGED_MANUAL" "$MANUAL_DIR"
updated=true

if [[ -d $BACKUP_MANUAL ]]; then
  rip "$BACKUP_MANUAL" >/dev/null
fi
rmdir "$TMP_PARENT"
TMP_PARENT=""

echo "✅ NixOS manual updated from nixpkgs@$NIXPKGS_REV_SHORT"
echo "   Location: $MANUAL_DIR"
echo ""

# Ask for commit approval
if [[ -t 0 ]]; then
  read -rp "📝 Commit changes? [y/N] " response
else
  response=""
  echo "Non-interactive shell; skipped commit prompt."
fi
if [[ $response =~ ^[Yy]$ ]]; then
  git add "$MANUAL_DIR"
  git commit -m "$(
    cat <<EOF
docs(nixos-manual): update from nixpkgs@${NIXPKGS_REV_SHORT}

Source: https://github.com/NixOS/nixpkgs/tree/${NIXPKGS_REV}/nixos/doc/manual
EOF
  )"
  echo "✅ Committed"
else
  echo "⏭️  Skipped commit"
fi
