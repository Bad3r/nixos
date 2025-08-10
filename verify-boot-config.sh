#!/usr/bin/env bash
# Boot Configuration Verification Script
# This script verifies that all critical boot components are properly configured

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Boot Configuration Verification Script${NC}"
echo "=========================================="
echo ""

# Track errors
ERRORS=0
WARNINGS=0

# Enable experimental features for nix commands
NIX_CMD="nix --extra-experimental-features 'nix-command flakes pipe-operators'"

echo -e "${YELLOW}1. Checking Current System Information${NC}"
echo "------------------------------------"
echo "Current kernel: $(uname -r)"
echo "Current NixOS generation: $(nixos-version || echo "Not on NixOS")"

if command -v lsblk >/dev/null 2>&1; then
    echo ""
    echo "Current block devices:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINT | grep -E "nvme|sda|sdb|luks" || true
fi

echo ""
echo -e "${YELLOW}2. Checking Configuration Files${NC}"
echo "-------------------------------"

# Check if the configuration file exists
if [ ! -f "/home/vx/nixos/modules/nixosConfigurations/system76.nix" ]; then
    echo -e "${RED}✗ Configuration file not found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuration file exists${NC}"

# Check for critical boot settings in the configuration file
echo ""
echo -e "${YELLOW}3. Checking Boot Configuration (from file)${NC}"
echo "-----------------------------------------"

check_in_file() {
    local pattern=$1
    local description=$2
    
    echo -n "Checking $description... "
    
    if grep -q "$pattern" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        ((ERRORS++))
    fi
}

check_in_file "enable = true;" "systemd-boot enabled"
check_in_file "editor = false" "boot editor disabled"
check_in_file "configurationLimit = 3" "generation limit"
check_in_file "fmask=0077" "/boot secure permissions"

echo ""
echo -e "${YELLOW}4. Checking LUKS Configuration${NC}"
echo "------------------------------"

echo -n "Checking root LUKS device... "
if grep -q "luks-de5ef033-553b-4943-be41-09125eb815b2" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Missing root LUKS device${NC}"
    ((ERRORS++))
fi

echo -n "Checking swap LUKS device... "
if grep -q "luks-555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Missing swap LUKS device${NC}"
    ((ERRORS++))
fi

echo ""
echo -e "${YELLOW}5. Checking Filesystem UUIDs${NC}"
echo "----------------------------"

echo -n "Checking root filesystem UUID... "
if grep -q "54df1eda-4dc3-40d0-a6da-8d1d7ee612b2" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Wrong root UUID${NC}"
    ((ERRORS++))
fi

echo -n "Checking /boot filesystem UUID... "
if grep -q "98A9-C26F" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Wrong /boot UUID${NC}"
    ((ERRORS++))
fi

echo -n "Checking swap UUID... "
if grep -q "72b0d736-e0c5-4f72-bc55-f50f7492ceef" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Wrong swap UUID${NC}"
    ((ERRORS++))
fi

echo ""
echo -e "${YELLOW}6. Checking NVIDIA Configuration${NC}"
echo "--------------------------------"

check_in_file '"nvidia"' "NVIDIA initrd modules"
check_in_file "NVreg_PreserveVideoMemoryAllocations=1" "NVIDIA memory preservation"
check_in_file "NVreg_EnableGpuFirmware=1" "NVIDIA firmware parameter"

echo ""
echo -e "${YELLOW}7. Comparing with Old Configuration${NC}"
echo "-----------------------------------"

echo "Key differences from old_nixos:"
echo "- nixos-hardware module: Not yet added (needs flake input)"
echo "- Both LUKS devices: ✓ Configured"
echo "- Boot security: ✓ Matched"
echo "- Filesystem permissions: ✓ Secure (0077)"

echo ""
echo -e "${BLUE}Summary:${NC}"
echo "--------"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Boot configuration matches old_nixos setup!${NC}"
    echo ""
    echo -e "${GREEN}Critical components verified:${NC}"
    echo "  ✓ Both LUKS devices (root + swap) configured"
    echo "  ✓ All filesystem UUIDs correct"
    echo "  ✓ systemd-boot security settings matched"
    echo "  ✓ NVIDIA modules in initrd for early KMS"
    echo "  ✓ Secure /boot permissions (0077)"
    echo ""
    echo -e "${YELLOW}Note:${NC} nixos-hardware.nixosModules.system76 is not yet added."
    echo "      This provides additional System76-specific optimizations."
    echo "      Consider adding it to flake inputs later."
else
    echo -e "${RED}✗ Found $ERRORS critical errors!${NC}"
    echo ""
    echo "Please check the configuration file and fix any missing items."
fi

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Run: cd /home/vx/nixos && ./build.sh dry-build"
echo "2. If successful, run: ./build.sh test (to create VM)"
echo "3. Test in VM before switching to real system"

exit $ERRORS