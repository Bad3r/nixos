#!/usr/bin/env bash
# Dendritic Migration Validation Script
# Checks current configuration against migration targets

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Dendritic Migration Validation ===${NC}"
echo ""

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Function to check status
check() {
  local name="$1"
  local condition="$2"

  if eval "$condition" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} $name"
    ((PASSED++))
  else
    echo -e "${RED}✗${NC} $name"
    ((FAILED++))
  fi
}

# Function for warnings
warn() {
  local name="$1"
  local condition="$2"

  if eval "$condition" 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC} $name"
    ((WARNINGS++))
  fi
}

# Section header
section() {
  echo ""
  echo -e "${BLUE}$1${NC}"
  echo "----------------------------------------"
}

# 1. Compliance Checks
section "1. Dendritic Pattern Compliance"

check "No module headers" \
  "! grep -r '^#' modules/ --include='*.nix' | grep -v '.nix:' > /dev/null 2>&1"

check "abort-on-warn enabled" \
  "grep -q 'abort-on-warn.*=.*true' flake.nix"

check "pipe-operators enabled" \
  "grep -q 'pipe-operators' flake.nix"

check "No tests directory" \
  "! [ -d tests ]"

check "No scripts directory" \
  "! [ -d scripts ]"

check "No filesystem config in imports.nix" \
  "! grep -q 'fileSystems\.' modules/system76/imports.nix 2>/dev/null"

# 2. Critical Infrastructure
section "2. Critical Infrastructure"

check "System76 hardware module exists" \
  "[ -f modules/hardware/system76.nix ]"

check "Enhanced NVIDIA configuration" \
  "grep -q 'NVreg_PreserveVideoMemoryAllocations' modules/nvidia-gpu.nix 2>/dev/null"

check "Boot compression configured" \
  "[ -f modules/boot/compression.nix ]"

check "SSH X11 forwarding" \
  "grep -q 'X11Forwarding.*=.*true' modules/networking/ssh.nix 2>/dev/null"

check "VSCode Remote module exists" \
  "[ -f modules/development/vscode-remote.nix ]"

# 3. Development Tools
section "3. Development Tools"

check "Docker configuration enhanced" \
  "grep -q 'docker-compose' modules/virtualization/docker.nix 2>/dev/null"

check "Development languages module" \
  "[ -f modules/development/languages.nix ]"

check "AI tools module" \
  "[ -f modules/development/ai-tools.nix ]"

warn "Clojure in packages" \
  "grep -q 'clojure' modules/development/languages.nix 2>/dev/null"

warn "Node.js 24 configured" \
  "grep -q 'nodejs_24' modules/development/vscode-remote.nix 2>/dev/null"

# 4. System Features
section "4. System Features"

check "Enhanced Tailscale configuration" \
  "grep -q 'useRoutingFeatures' modules/networking/vpn.nix 2>/dev/null"

check "Media tools module" \
  "[ -f modules/pc/media-tools.nix ]"

check "Communication apps module" \
  "[ -f modules/pc/communication.nix ]"

warn "TeamViewer service" \
  "grep -q 'teamviewer' modules/pc/communication.nix 2>/dev/null"

# 5. Optional Features
section "5. Optional Advanced Features"

warn "Impermanence module" \
  "[ -f modules/impermanence.nix ]"

warn "Plasma Manager module" \
  "[ -f modules/plasma-manager.nix ]"

warn "Custom packages overlay" \
  "[ -f modules/meta/custom-packages.nix ]"

# 6. Package Availability Check
section "6. Package Availability"

echo "Checking for key packages in configuration..."

# Function to check if package is available
check_package() {
  local pkg="$1"
  if grep -rq "$pkg" modules/ --include="*.nix" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $pkg"
  else
    echo -e "  ${RED}✗${NC} $pkg (missing)"
  fi
}

# Check critical packages
echo "Critical packages:"
check_package "bat"
check_package "ripgrep"
check_package "fd"
check_package "neovim"
check_package "docker"
check_package "mpv"
check_package "firefox"

# 7. Build Status
section "7. Build Status"

echo "Testing build (this may take a moment)..."
if nix build .#nixosConfigurations.system76.config.system.build.toplevel \
  --extra-experimental-features "nix-command flakes pipe-operators" \
  --dry-run 2>/dev/null; then
  echo -e "${GREEN}✓${NC} Configuration builds successfully"
  ((PASSED++))
else
  echo -e "${RED}✗${NC} Build failed"
  ((FAILED++))
fi

# 8. Flake Inputs
section "8. Flake Input Status"

check_input() {
  local input="$1"
  if grep -q "inputs.$input" flake.nix 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $input"
  else
    echo -e "  ${YELLOW}⚠${NC} $input (not configured)"
  fi
}

echo "Checking flake inputs..."
check_input "nixpkgs"
check_input "home-manager"
check_input "flake-parts"
check_input "stylix"
check_input "nixos-hardware"
check_input "impermanence"
check_input "plasma-manager"

# Summary
section "Summary"

TOTAL=$((PASSED + FAILED))
COMPLETION=$((PASSED * 100 / TOTAL))

echo -e "Passed:   ${GREEN}$PASSED${NC}"
echo -e "Failed:   ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""
echo -e "Compliance Score: ${BLUE}$COMPLETION%${NC}"

if [ $COMPLETION -eq 100 ]; then
  echo -e "${GREEN}Perfect compliance achieved!${NC}"
elif [ $COMPLETION -ge 90 ]; then
  echo -e "${GREEN}Excellent progress!${NC}"
elif [ $COMPLETION -ge 70 ]; then
  echo -e "${YELLOW}Good progress, keep going!${NC}"
else
  echo -e "${RED}Significant work remains.${NC}"
fi

# Migration status
echo ""
section "Migration Phase Status"

if [ -f modules/hardware/system76.nix ] &&
  [ -f modules/development/vscode-remote.nix ] &&
  [ -f modules/boot/compression.nix ]; then
  echo -e "${GREEN}✓ Phase 1: Critical Infrastructure - COMPLETE${NC}"
else
  echo -e "${YELLOW}⚠ Phase 1: Critical Infrastructure - IN PROGRESS${NC}"
fi

if [ -f modules/development/languages.nix ] &&
  [ -f modules/pc/media-tools.nix ]; then
  echo -e "${GREEN}✓ Phase 2: Development Workflow - COMPLETE${NC}"
elif [ -f modules/development/languages.nix ] ||
  [ -f modules/pc/media-tools.nix ]; then
  echo -e "${YELLOW}⚠ Phase 2: Development Workflow - IN PROGRESS${NC}"
else
  echo -e "${RED}✗ Phase 2: Development Workflow - NOT STARTED${NC}"
fi

if [ -f modules/impermanence.nix ] ||
  [ -f modules/plasma-manager.nix ]; then
  echo -e "${YELLOW}⚠ Phase 3: Optional Features - IN PROGRESS${NC}"
else
  echo -e "${RED}✗ Phase 3: Optional Features - NOT STARTED${NC}"
fi

# Recommendations
echo ""
section "Next Steps"

if [ $FAILED -gt 0 ]; then
  echo "Priority fixes needed:"

  if ! [ -f modules/hardware/system76.nix ]; then
    echo "  1. Run: ./execute-phase1.sh"
  fi

  if ! grep -q 'X11Forwarding.*=.*true' modules/networking/ssh.nix 2>/dev/null; then
    echo "  2. Update SSH configuration for X11 forwarding"
  fi

  if ! [ -f modules/development/vscode-remote.nix ]; then
    echo "  3. Create VSCode Remote support module"
  fi

  echo ""
  echo "Refer to DENDRITIC_MIGRATION_PLAN.md for detailed instructions."
else
  echo -e "${GREEN}All checks passed! Configuration is fully migrated.${NC}"
fi

echo ""
echo "Run this script anytime to check migration progress."
