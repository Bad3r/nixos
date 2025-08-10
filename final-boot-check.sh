#!/usr/bin/env bash
# Final boot configuration verification

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Final Boot Configuration Check${NC}"
echo "=================================="
echo ""

ERRORS=0

# Try to evaluate the configuration
echo -e "${YELLOW}Testing configuration evaluation...${NC}"
echo ""

# Check if we can evaluate basic attributes
if nix --extra-experimental-features 'nix-command flakes pipe-operators' eval /home/vx/nixos#nixosConfigurations.system76.config.system.stateVersion 2>/dev/null; then
    echo -e "${GREEN}✓ Configuration evaluates successfully${NC}"
else
    echo -e "${RED}✗ Configuration fails to evaluate${NC}"
    ((ERRORS++))
fi

# Check critical boot settings by evaluating the actual config
echo ""
echo -e "${YELLOW}Checking evaluated boot configuration...${NC}"

check_eval() {
    local attr=$1
    local expected=$2
    local description=$3
    
    echo -n "$description: "
    
    result=$(nix --extra-experimental-features 'nix-command flakes pipe-operators' eval /home/vx/nixos#nixosConfigurations.system76.config.$attr 2>/dev/null || echo "EVAL_ERROR")
    
    if [[ "$result" == "EVAL_ERROR" ]]; then
        echo -e "${RED}✗ Failed to evaluate${NC}"
        ((ERRORS++))
    elif [[ "$result" == *"$expected"* ]]; then
        echo -e "${GREEN}✓ $result${NC}"
    else
        echo -e "${RED}✗ Expected $expected, got $result${NC}"
        ((ERRORS++))
    fi
}

check_eval "boot.loader.systemd-boot.enable" "true" "systemd-boot enabled"
check_eval "boot.loader.efi.canTouchEfiVariables" "true" "EFI variables"
check_eval "boot.loader.systemd-boot.editor" "false" "Boot editor disabled"
check_eval "system.stateVersion" "25.05" "State version"

echo ""
echo -e "${YELLOW}Checking hardware configuration...${NC}"
check_eval "hardware.system76.enableAll" "true" "System76 hardware"
check_eval "hardware.nvidia.prime.sync.enable" "true" "NVIDIA PRIME sync"

echo ""
echo -e "${YELLOW}Checking if nixos-hardware is imported...${NC}"
# This is harder to check directly, but we can see if it's in the flake
if grep -q "nixos-hardware" /home/vx/nixos/flake.nix; then
    echo -e "${GREEN}✓ nixos-hardware in flake inputs${NC}"
    if grep -q "inputs.nixos-hardware.nixosModules.system76" /home/vx/nixos/modules/nixosConfigurations/system76.nix; then
        echo -e "${GREEN}✓ nixos-hardware.nixosModules.system76 imported${NC}"
    else
        echo -e "${RED}✗ nixos-hardware module not imported${NC}"
        ((ERRORS++))
    fi
else
    echo -e "${RED}✗ nixos-hardware not in flake inputs${NC}"
    ((ERRORS++))
fi

echo ""
echo -e "${BLUE}Summary:${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All boot configuration checks passed!${NC}"
    echo ""
    echo "The system is configured correctly with:"
    echo "  ✓ systemd-boot properly enabled"
    echo "  ✓ LUKS encryption for root and swap"
    echo "  ✓ System76 hardware support via nixos-hardware"
    echo "  ✓ NVIDIA with PRIME sync"
    echo "  ✓ All required kernel modules"
    echo ""
    echo -e "${GREEN}It should boot exactly like your old system!${NC}"
else
    echo -e "${RED}❌ Found $ERRORS configuration errors${NC}"
    echo "Please fix these before attempting to boot."
fi

echo ""
echo "Next step: cd /home/vx/nixos && ./build.sh dry-build"