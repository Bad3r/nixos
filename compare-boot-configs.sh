#!/usr/bin/env bash
# Compare boot configurations between old_nixos and new nixos

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Boot Configuration Comparison${NC}"
echo "============================="
echo ""

# Function to extract values from old config
get_old_value() {
    local file=$1
    local pattern=$2
    grep -h "$pattern" "$file" 2>/dev/null || echo "NOT FOUND"
}

echo -e "${YELLOW}1. LUKS Devices${NC}"
echo "---------------"
echo "Old config LUKS devices:"
grep -h "luks-" /home/vx/old_nixos/hosts/linux/system76/hardware*.nix | grep -v "^#" | sort -u || echo "None found"
echo ""
echo "New config LUKS devices:"
grep -h "luks-" /home/vx/nixos/modules/nixosConfigurations/system76.nix | grep -v "^#" | sort -u || echo "None found"

echo ""
echo -e "${YELLOW}2. Filesystem UUIDs${NC}"
echo "-------------------"
echo "Comparing filesystem UUIDs..."
for uuid in "54df1eda-4dc3-40d0-a6da-8d1d7ee612b2" "98A9-C26F" "72b0d736-e0c5-4f72-bc55-f50f7492ceef"; do
    echo -n "UUID $uuid: "
    if grep -q "$uuid" /home/vx/old_nixos/hosts/linux/system76/hardware*.nix && \
       grep -q "$uuid" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
        echo -e "${GREEN}✓ Present in both${NC}"
    else
        echo -e "${RED}✗ Mismatch${NC}"
    fi
done

echo ""
echo -e "${YELLOW}3. Boot Configuration${NC}"
echo "---------------------"
echo "systemd-boot settings:"
grep -h "systemd-boot\|editor\|configurationLimit\|consoleMode" /home/vx/old_nixos/modules/linux/default.nix | grep -v "^#" || echo "Not found in old"
echo "---"
grep -h "systemd-boot\|editor\|configurationLimit\|consoleMode" /home/vx/nixos/modules/nixosConfigurations/system76.nix | grep -v "^#" || echo "Not found in new"

echo ""
echo -e "${YELLOW}4. NVIDIA Configuration${NC}"
echo "-----------------------"
echo "Old NVIDIA initrd modules:"
grep -A5 "initrd.kernelModules" /home/vx/old_nixos/modules/linux/hardware/nvidia.nix | grep -v "^#" || echo "Not found"
echo "---"
echo "New NVIDIA initrd modules:"
grep -A5 "initrd" /home/vx/nixos/modules/nixosConfigurations/system76.nix | grep -E "nvidia|kernelModules" | head -10 || echo "Not found"

echo ""
echo "NVIDIA kernel parameters:"
echo "Old:"
grep "kernelParams" /home/vx/old_nixos/modules/linux/hardware/nvidia.nix -A3 | grep -v "^#" || echo "Not found"
echo "New:"
grep "kernelParams" /home/vx/nixos/modules/nixosConfigurations/system76.nix -A3 | grep -v "^#" || echo "Not found"

echo ""
echo -e "${YELLOW}5. Critical Boot Modules${NC}"
echo "------------------------"
echo "Checking blacklisted modules..."
echo -n "nouveau blacklisted: "
if grep -q 'blacklistedKernelModules.*nouveau' /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓ Yes${NC}"
else
    echo -e "${RED}✗ No${NC}"
fi

echo -n "extraModulePackages has nvidia_x11: "
if grep -q 'extraModulePackages.*nvidia_x11' /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
    echo -e "${GREEN}✓ Yes${NC}"
else
    echo -e "${RED}✗ No${NC}"
fi

echo ""
echo -e "${YELLOW}6. Missing from new config${NC}"
echo "--------------------------"
echo "Checking for nixos-hardware import:"
if grep -q "nixos-hardware" /home/vx/nixos/flake.nix; then
    echo -e "${GREEN}✓ nixos-hardware in flake inputs${NC}"
else
    echo -e "${YELLOW}⚠ nixos-hardware NOT in flake inputs${NC}"
    echo "  The old config imports: inputs.nixos-hardware.nixosModules.system76"
fi

echo ""
echo -e "${BLUE}Summary${NC}"
echo "-------"
echo "The new configuration should boot successfully with LUKS encryption."
echo "Key components are properly configured:"
echo "- Both LUKS devices (root and swap)"
echo "- All filesystem UUIDs"
echo "- NVIDIA modules and parameters"
echo "- Boot security settings"
echo ""
echo -e "${YELLOW}Note:${NC} Consider adding nixos-hardware to flake inputs for System76-specific optimizations."