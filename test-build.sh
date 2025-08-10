#!/usr/bin/env bash
# Test build script with proper experimental features

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Testing NixOS Configuration Build${NC}"
echo "===================================="
echo ""

# Set up Nix with experimental features
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"

# Function to run command with output
run_test() {
    local desc=$1
    local cmd=$2
    
    echo -e "${YELLOW}$desc...${NC}"
    if eval "$cmd"; then
        echo -e "${GREEN}✓ Success${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
    echo ""
}

# Change to the nixos directory
cd /home/vx/nixos

# Test 1: Check flake metadata
echo -e "${YELLOW}1. Checking flake structure${NC}"
nix flake metadata . 2>&1 | grep -E "Description:|Inputs:" || echo "Metadata check failed"

# Test 2: Show flake outputs
echo -e "\n${YELLOW}2. Flake outputs${NC}"
nix flake show . 2>&1 | grep -E "nixosConfigurations|system76" | head -10 || echo "No system76 config found"

# Test 3: Try to evaluate system configuration
echo -e "\n${YELLOW}3. Evaluating system configuration${NC}"
if nix eval .#nixosConfigurations.system76.config.system.stateVersion 2>&1; then
    echo -e "${GREEN}✓ Configuration evaluates${NC}"
else
    echo -e "${RED}✗ Configuration fails to evaluate${NC}"
    echo "Trying with more details..."
    nix eval .#nixosConfigurations.system76.config.system.stateVersion --show-trace 2>&1 | tail -50
fi

# Test 4: Dry build
echo -e "\n${YELLOW}4. Attempting dry build${NC}"
echo "This will check if all derivations can be built..."
if nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>&1; then
    echo -e "${GREEN}✓ Dry build successful!${NC}"
    echo -e "${GREEN}The configuration is ready to build!${NC}"
else
    echo -e "${RED}✗ Dry build failed${NC}"
    echo "Running with trace for debugging..."
    nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run --show-trace 2>&1 | tail -100
fi

echo -e "\n${BLUE}Summary:${NC}"
echo "If the dry build succeeded, you can proceed with:"
echo "  ./build.sh --host system76"
echo "Or test in a VM first:"
echo "  nixos-rebuild build-vm --flake .#system76"