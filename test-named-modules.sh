#!/usr/bin/env bash
# Test script to verify named module compliance
set -euo pipefail

echo "Verifying named module compliance..."

# These SHOULD exist (correct named modules)
SHOULD_EXIST="nvidia-gpu"
for module in $SHOULD_EXIST; do
  if nix eval .#flake.modules.nixos.$module 2>/dev/null; then
    echo "✓ $module correctly exists as named module"
  else
    echo "✗ ERROR: $module missing (should exist)"
    exit 1
  fi
done

# These should NOT exist (improper named modules)
SHOULD_NOT_EXIST="system76-complete custom-packages home-manager-setup"
ERRORS=0
for module in $SHOULD_NOT_EXIST; do
  if nix eval .#flake.modules.nixos.$module 2>/dev/null; then
    echo "✗ ERROR: $module still exists as named module (should be removed)"
    ERRORS=$((ERRORS + 1))
  else
    echo "✓ $module correctly removed"
  fi
done

if [ $ERRORS -eq 0 ]; then
  echo "✅ All named modules correctly configured!"
  exit 0
else
  echo "❌ $ERRORS modules still improperly defined"
  exit 1
fi