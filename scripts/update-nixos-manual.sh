#!/usr/bin/env bash
# shellcheck shell=bash
# update-nixos-manual.sh
# Downloads the NixOS manual markdown sources from the flake's nixpkgs input
# Usage: ./scripts/update-nixos-manual.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANUAL_DIR="$REPO_ROOT/nixos-manual"

cd "$REPO_ROOT"

echo "📥 Fetching nixpkgs path from flake input..."
NIXPKGS_PATH=$(nix eval --raw --impure --expr '(builtins.getFlake "git+file:///home/vx/nixos").inputs.nixpkgs.outPath')
NIXPKGS_REV=$(nix eval --raw --impure --expr '(builtins.getFlake "git+file:///home/vx/nixos").inputs.nixpkgs.rev')
NIXPKGS_REV_SHORT="${NIXPKGS_REV:0:7}"

echo "   nixpkgs revision: $NIXPKGS_REV_SHORT"

# Remove existing manual directory
if [[ -d $MANUAL_DIR ]]; then
  echo "🗑️  Removing existing nixos-manual directory..."
  rm -rf "$MANUAL_DIR"
fi

# Copy manual from nixpkgs
echo "📋 Copying manual from nixpkgs..."
cp -r "$NIXPKGS_PATH/nixos/doc/manual" "$MANUAL_DIR"

# Make readable and writable by all users
echo "🔓 Setting permissions..."
sudo chmod -R a+rw "$MANUAL_DIR"

echo "✅ NixOS manual updated from nixpkgs@$NIXPKGS_REV_SHORT"
echo "   Location: $MANUAL_DIR"
echo ""

# Ask for commit approval
read -rp "📝 Commit changes? [y/N] " response
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
