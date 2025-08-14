#!/usr/bin/env bash
# Dendritic Migration Phase 1 Execution Script
# This script automates the critical first phase of migration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Dendritic Migration Phase 1: Critical Infrastructure ===${NC}"
echo ""

# Function to check if a command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        exit 1
    fi
}

# Function to create backup
create_backup() {
    echo -e "${YELLOW}Creating backup...${NC}"
    git add -A
    git commit -m "backup: before phase 1 migration" || true
    git tag backup-phase1-$(date +%Y%m%d-%H%M%S) || true
    check_status "Backup created"
}

# Step 1: Fix Compliance Issues
fix_compliance() {
    echo -e "\n${YELLOW}Step 1: Fixing compliance issues...${NC}"
    
    # Backup imports.nix
    if [ -f modules/system76/imports.nix ]; then
        cp modules/system76/imports.nix modules/system76/imports.nix.backup
        check_status "Backed up imports.nix"
    fi
    
    # Remove tests and scripts directories
    if [ -d tests ]; then
        tar -czf tests-archive-$(date +%Y%m%d).tar.gz tests/
        rm -rf tests/
        check_status "Archived and removed tests directory"
    fi
    
    if [ -d scripts ]; then
        tar -czf scripts-archive-$(date +%Y%m%d).tar.gz scripts/
        rm -rf scripts/
        check_status "Archived and removed scripts directory"
    fi
}

# Step 2: Create System76 Hardware Module
create_system76_module() {
    echo -e "\n${YELLOW}Step 2: Creating System76 hardware module...${NC}"
    
    mkdir -p modules/hardware
    
    cat > modules/hardware/system76.nix << 'EOF'
{ config, lib, ... }:
{
  flake.modules.nixos.system76-hardware = { pkgs, ... }: {
    hardware.system76.power-daemon.enable = true;
    hardware.system76.kernel-modules.enable = true;
    
    environment.systemPackages = with pkgs; [
      system76-power
      system76-firmware
      system76-keyboard-configurator
    ];
  };
}
EOF
    check_status "Created system76 hardware module"
}

# Step 3: Enhanced NVIDIA Configuration
enhance_nvidia() {
    echo -e "\n${YELLOW}Step 3: Enhancing NVIDIA configuration...${NC}"
    
    cat > modules/nvidia-gpu.nix << 'EOF'
{ lib, ... }:
{
  flake.modules.nixos.nvidia-gpu = { pkgs, ... }: {
    specialisation.nvidia-gpu.configuration = {
      services.xserver.videoDrivers = [ "nvidia" ];
      
      boot.kernelParams = [
        "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
        "nvidia.NVreg_EnableGpuFirmware=1"
      ];
      
      boot.blacklistedKernelModules = [ "nouveau" ];
      boot.initrd.kernelModules = [ 
        "nvidia" 
        "nvidia_modeset" 
        "nvidia_uvm" 
        "nvidia_drm" 
      ];
      
      hardware.graphics.extraPackages = with pkgs; [
        nvidia-vaapi-driver
        vaapiVdpau
        libvdpau-va-gl
      ];
    };
  };
  
  nixpkgs.allowedUnfreePackages = [
    "nvidia-x11"
    "nvidia-settings"
  ];
}
EOF
    check_status "Enhanced NVIDIA configuration"
}

# Step 4: Boot Compression Module
create_boot_compression() {
    echo -e "\n${YELLOW}Step 4: Creating boot compression module...${NC}"
    
    cat > modules/boot/compression.nix << 'EOF'
{ config, lib, ... }:
{
  flake.modules.nixos.base = {
    boot.initrd.compressor = "zstd";
    boot.loader.systemd-boot.configurationLimit = 3;
    boot.loader.systemd-boot.editor = false;
    boot.loader.systemd-boot.consoleMode = "auto";
  };
}
EOF
    check_status "Created boot compression module"
}

# Step 5: VSCode Remote Support
create_vscode_remote() {
    echo -e "\n${YELLOW}Step 5: Creating VSCode Remote support module...${NC}"
    
    cat > modules/development/vscode-remote.nix << 'EOF'
{ config, lib, ... }:
{
  flake.modules.nixos.vscode-remote = { pkgs, ... }: {
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # Core libraries
        curl
        icu
        freetype
        fontconfig
        libxml2
        libxslt
        nspr
        nss
        
        # Graphics
        libGL
        libva
        
        # GTK and dependencies
        gtk3
        cairo
        pango
        gdk-pixbuf
        
        # X11
        xorg.libX11
        xorg.libXcomposite
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXrender
        xorg.libXtst
        xorg.libxcb
        
        # Additional libraries
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        cups
        dbus
        expat
        glib
        libdrm
        libnotify
        libpulseaudio
        libuuid
        libxkbcommon
        mesa
        openssl
        pciutils
        pipewire
        systemd
        vulkan-loader
        wayland
        zlib
      ];
    };
    
    environment.systemPackages = with pkgs; [
      nodejs_24
      (writeShellScriptBin "fix-vscode-server" ''
        # Helper script for VSCode Server issues
        SERVER_DIR="$HOME/.vscode-server"
        if [ -d "$SERVER_DIR" ]; then
          find "$SERVER_DIR" -name "node" -type f -exec \
            patchelf --set-interpreter ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 {} \;
        fi
      '')
    ];
    
    programs.ssh.extraConfig = ''
      Host *
        SetEnv PATH=/run/current-system/sw/bin:/usr/bin:/bin
    '';
  };
}
EOF
    check_status "Created VSCode Remote support module"
}

# Step 6: Test Build
test_build() {
    echo -e "\n${YELLOW}Step 6: Testing build...${NC}"
    
    # Format check
    nix fmt 2>/dev/null || true
    
    # Build test
    echo "Building configuration (this may take a while)..."
    if nix build .#nixosConfigurations.system76.config.system.build.toplevel \
        --extra-experimental-features "nix-command flakes pipe-operators" 2>/dev/null; then
        check_status "Build successful"
    else
        echo -e "${RED}Build failed. Check the configuration.${NC}"
        echo "To debug, run:"
        echo "  nix build .#nixosConfigurations.system76.config.system.build.toplevel --show-trace"
        exit 1
    fi
}

# Step 7: Compliance Check
check_compliance() {
    echo -e "\n${YELLOW}Step 7: Checking compliance...${NC}"
    
    # Check for headers
    if grep -r "^#" modules/ --include="*.nix" | grep -v ".nix:" > /dev/null 2>&1; then
        echo -e "${RED}✗${NC} Found module headers (non-compliant)"
    else
        check_status "No module headers found"
    fi
    
    # Check abort-on-warn
    if grep -q "abort-on-warn.*=.*true" flake.nix; then
        check_status "abort-on-warn is enabled"
    else
        echo -e "${RED}✗${NC} abort-on-warn not enabled"
    fi
    
    # Check pipe-operators
    if grep -q "pipe-operators" flake.nix; then
        check_status "pipe-operators enabled"
    else
        echo -e "${RED}✗${NC} pipe-operators not enabled"
    fi
    
    # Count modules
    MODULE_COUNT=$(find modules -name "*.nix" -type f | wc -l)
    echo -e "${GREEN}✓${NC} Total modules: $MODULE_COUNT"
}

# Main execution
main() {
    echo "This script will execute Phase 1 of the Dendritic Migration Plan"
    echo "It will create critical infrastructure modules and fix compliance issues"
    echo ""
    read -p "Do you want to proceed? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    
    create_backup
    fix_compliance
    create_system76_module
    enhance_nvidia
    create_boot_compression
    create_vscode_remote
    test_build
    check_compliance
    
    echo ""
    echo -e "${GREEN}=== Phase 1 Complete ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Review the changes with: git diff"
    echo "2. Test the configuration with: sudo nixos-rebuild dry-build --flake .#system76"
    echo "3. If everything looks good, apply with: sudo nixos-rebuild switch --flake .#system76"
    echo "4. Continue with Phase 2 using the DENDRITIC_MIGRATION_PLAN.md"
    echo ""
    echo "To rollback if needed:"
    echo "  git reset --hard backup-phase1-*"
    echo "  sudo nixos-rebuild switch --rollback"
}

# Run main function
main "$@"