#!/usr/bin/env bash
# Dendritic Pattern Compliance Test (Corrected Version)
# Based on actual requirements from mightyiam/infra golden standard

set -euo pipefail

# Enable pipe operators for nix commands
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

# Helper functions
check_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

check_fail() {
  echo -e "${RED}✗${NC} $1: $2"
  FAIL=$((FAIL + 1))
}

check_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  WARN=$((WARN + 1))
}

echo -e "${BLUE}=== Dendritic Pattern Compliance Test ===${NC}"
echo ""

# 1. Check abort-on-warn in flake.nix (REQUIRED)
echo "Checking flake.nix configuration..."
if grep -q "abort-on-warn.*=.*true" flake.nix; then
  check_pass "abort-on-warn is set to true"
else
  check_fail "nixConfig" "Missing abort-on-warn = true"
fi

# 2. Check pipe operators in flake.nix
if grep -q "pipe-operators" flake.nix; then
  check_pass "Pipe operators in flake.nix"
else
  check_fail "nixConfig" "Missing pipe-operators in extra-experimental-features"
fi

# 3. Check pipe operators in scripts (via NIX_CONFIG or flags)
echo ""
echo "Checking scripts for pipe operators..."
for script in *.sh; do
  [ -f "$script" ] || continue
  # Skip this compliance test script itself
  [ "$script" = "test-dendritic-compliance.sh" ] && continue
  # Skip compare-boot-configs.sh as it doesn't use nix commands
  [ "$script" = "compare-boot-configs.sh" ] && continue
  # Skip scripts that don't use nix commands
  if ! grep -q "nix " "$script" 2>/dev/null && ! grep -q "nixos-rebuild" "$script" 2>/dev/null; then
    continue
  fi
  
  if grep -q "pipe-operators" "$script" || grep -q "NIX_CONFIG.*pipe-operators" "$script"; then
    check_pass "$script has pipe operators"
  else
    check_fail "$script" "Missing pipe operators configuration"
  fi
done

# 4. Check host configuration pattern
echo ""
echo "Checking host configuration pattern..."
if grep -r "configurations.nixos.system76.module" modules/hosts/system76/ --include="*.nix" > /dev/null 2>&1; then
  check_pass "Correct host configuration pattern"
else
  check_fail "Host configuration" "Wrong pattern - should use configurations.nixos.system76.module"
fi

# 5. Check for literal imports
echo ""
echo "Checking for literal path imports..."
if timeout 5 grep -r "imports.*\\./" modules/ --include="*.nix" 2>/dev/null | head -1 > /dev/null; then
  LITERAL_COUNT=$(timeout 5 grep -r "imports.*\\./" modules/ --include="*.nix" 2>/dev/null | wc -l)
  check_fail "Imports" "Found $LITERAL_COUNT literal path imports"
  echo "  Files with literal imports:"
  timeout 2 grep -r "imports.*\\./" modules/ --include="*.nix" 2>/dev/null | cut -d: -f1 | sort -u | head -5
else
  check_pass "No literal path imports"
fi

# 6. Check import-tree usage
echo ""
echo "Checking import-tree usage..."
if grep -q "import-tree.*modules" flake.nix; then
  check_pass "Using import-tree for module loading"
else
  check_fail "Module loading" "Not using import-tree"
fi

# 7. Check state version is hardcoded (this is CORRECT per golden standard)
echo ""
echo "Checking state version..."
if grep -r "system.stateVersion.*=" modules/hosts/system76/ --include="*.nix" | grep -v "config.flake.meta" > /dev/null 2>&1; then
  check_pass "State version is hardcoded (correct per golden standard)"
else
  check_fail "State version" "Should be hardcoded, not from metadata"
fi

# 8. Check desktop namespace exists (should NOT be removed)
echo ""
echo "Checking namespace structure..."
if [ -d "modules/desktop" ]; then
  check_pass "Desktop namespace exists (correct - should be kept)"
else
  check_warn "Desktop namespace removed (was not necessary to remove)"
fi

# 9. Check for namespace consistency
echo ""
echo "Checking namespace consistency..."
NAMESPACE_ISSUES=0

# Check base modules
for file in modules/base/*.nix; do
  [ -f "$file" ] || continue
  if grep -q "flake.modules.nixos" "$file"; then
    if ! grep -q "flake.modules.nixos.base" "$file"; then
      NAMESPACE_ISSUES=$((NAMESPACE_ISSUES + 1))
      [ $NAMESPACE_ISSUES -le 3 ] && echo "  $(basename $file): Wrong namespace for base/"
    fi
  fi
done

# Check pc modules  
for file in modules/pc/*.nix; do
  [ -f "$file" ] || continue
  if grep -q "flake.modules.nixos" "$file"; then
    if ! grep -q "flake.modules.nixos.pc" "$file"; then
      NAMESPACE_ISSUES=$((NAMESPACE_ISSUES + 1))
      [ $NAMESPACE_ISSUES -le 3 ] && echo "  $(basename $file): Wrong namespace for pc/"
    fi
  fi
done

# Check workstation modules (can be workstation or named modules)
for file in modules/workstation/*.nix; do
  [ -f "$file" ] || continue
  if grep -q "flake.modules.nixos" "$file"; then
    if ! grep -E "flake.modules.nixos.(workstation|swap|security-tools)" "$file"; then
      NAMESPACE_ISSUES=$((NAMESPACE_ISSUES + 1))
      [ $NAMESPACE_ISSUES -le 3 ] && echo "  $(basename $file): Wrong namespace for workstation/"
    fi
  fi
done

if [ $NAMESPACE_ISSUES -eq 0 ]; then
  check_pass "All modules use correct namespaces"
else
  check_warn "Found $NAMESPACE_ISSUES modules with questionable namespaces"
fi

# 10. Check for mkForce usage (should prefer mkDefault)
echo ""
echo "Checking override patterns..."
MKFORCE_COUNT=$(grep -r "mkForce" modules --include="*.nix" 2>/dev/null | wc -l || echo "0")
if [ $MKFORCE_COUNT -eq 0 ]; then
  check_pass "No mkForce usage (uses mkDefault instead)"
elif [ $MKFORCE_COUNT -le 2 ]; then
  check_pass "Minimal mkForce usage ($MKFORCE_COUNT instances)"
else
  check_warn "Found $MKFORCE_COUNT mkForce uses - consider using mkDefault"
fi

# 11. Build test
echo ""
echo "Testing build (dry-run)..."
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
if timeout 30 nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>/dev/null; then
  check_pass "Configuration builds successfully"
else
  check_fail "Build test" "Configuration fails to build or timed out"
fi

# Final Report
echo ""
echo "======================================"
echo "       COMPLIANCE REPORT              "
echo "======================================"
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC} $FAIL"

TOTAL_CHECKS=$((PASS + FAIL))
if [ $TOTAL_CHECKS -gt 0 ]; then
  SCORE=$((PASS * 100 / TOTAL_CHECKS))
else
  SCORE=0
fi

echo ""
echo "Compliance Score: $SCORE/100"

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}✓ FULLY COMPLIANT WITH DENDRITIC PATTERN${NC}"
  echo ""
  echo "Your NixOS configuration follows the dendritic pattern correctly!"
  exit 0
elif [ $SCORE -ge 80 ]; then
  echo -e "${YELLOW}⚠ MOSTLY COMPLIANT (${SCORE}% achieved)${NC}"
  echo ""
  echo "Minor issues remain. Review failures above."
  exit 0
else
  echo -e "${RED}✗ NOT COMPLIANT${NC}"
  echo ""
  echo "Critical issues found. Fix failures above before proceeding."
  exit 1
fi