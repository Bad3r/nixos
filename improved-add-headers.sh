#!/usr/bin/env bash
# Script to add properly analyzed headers to Nix modules
# Part of Phase 3 of Dendritic Pattern remediation - IMPROVED VERSION

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Advanced Module Header Analysis and Addition ===${NC}"
echo ""

# Backup modules directory first
backup_dir="modules.backup.headers.$(date +%Y%m%d-%H%M%S)"
echo -e "${YELLOW}Creating backup at: $backup_dir${NC}"
cp -r modules/ "$backup_dir/"

# Function to extract actual namespace from Nix file
extract_namespace() {
    local file="$1"
    local namespace=""
    
    # Look for direct namespace declarations
    if grep -q 'flake\.modules\.nixos\."[^"]*"' "$file" 2>/dev/null; then
        # Named module pattern
        namespace=$(grep -oP 'flake\.modules\.nixos\."\K[^"]+' "$file" 2>/dev/null | head -1)
        if [ -n "$namespace" ]; then
            echo "nixos.$namespace"
            return
        fi
    fi
    
    # Check for attribute path assignments
    if grep -q 'flake\.modules\.nixos\.[a-zA-Z0-9_-]*\s*=' "$file" 2>/dev/null; then
        namespace=$(grep -oE 'flake\.modules\.nixos\.[a-zA-Z0-9_-]+' "$file" | sed 's/flake\.modules\.nixos\.//' | head -1)
        if [ -n "$namespace" ]; then
            echo "nixos.$namespace"
            return
        fi
    fi
    
    # Check for homeManager namespaces
    if grep -q 'flake\.modules\.homeManager\.' "$file" 2>/dev/null; then
        if grep -q 'flake\.modules\.homeManager\.gui' "$file"; then
            echo "homeManager.gui"
            return
        elif grep -q 'flake\.modules\.homeManager\.base' "$file"; then
            echo "homeManager.base"
            return
        fi
    fi
    
    # Check for configurations namespace
    if grep -q 'configurations\.nixos\.' "$file" 2>/dev/null; then
        echo "configurations"
        return
    fi
    
    # Check for perSystem
    if grep -q 'perSystem\s*=' "$file" 2>/dev/null; then
        echo "perSystem"
        return
    fi
    
    # Check for flake.meta
    if grep -q 'flake\.meta\.' "$file" 2>/dev/null; then
        echo "meta"
        return
    fi
    
    # Default to examining file path for clues
    local rel_path=$(echo "$file" | sed 's|modules/||')
    case "$rel_path" in
        system76/*) echo "configurations.system76" ;;
        pc/*) echo "nixos.pc" ;;
        home/base/*) echo "homeManager.base" ;;
        home/gui/*) echo "homeManager.gui" ;;
        meta/*) echo "meta" ;;
        boot/*) echo "nixos.boot" ;;
        style/*) echo "nixos.style" ;;
        *) echo "nixos" ;;
    esac
}

# Function to determine meaningful purpose from file content
determine_purpose() {
    local file="$1"
    local name=$(basename "$file" .nix)
    local content=$(cat "$file")
    
    # Special cases based on filename and content analysis
    case "$name" in
        nvidia-gpu)
            echo "NVIDIA GPU support with proprietary drivers and PRIME synchronization"
            ;;
        efi)
            echo "UEFI boot loader configuration with systemd-boot"
            ;;
        swap)
            echo "Swap space configuration with optional encryption support"
            ;;
        tmp)
            echo "Temporary filesystem configuration using tmpfs"
            ;;
        pc)
            echo "Base configuration for personal computers"
            ;;
        workstation)
            echo "Extended configuration for development workstations"
            ;;
        owner)
            echo "Central metadata configuration for owner and system settings"
            ;;
        sudo)
            echo "Sudo and privilege escalation configuration"
            ;;
        plasma)
            echo "KDE Plasma desktop environment configuration"
            ;;
        pipewire)
            echo "PipeWire audio system configuration with WirePlumber"
            ;;
        ssh)
            echo "OpenSSH server configuration with security hardening"
            ;;
        *)
            # Try to extract purpose from content
            if echo "$content" | grep -q "docker"; then
                echo "Docker containerization platform configuration"
            elif echo "$content" | grep -q "virtualbox"; then
                echo "VirtualBox virtualization configuration"
            elif echo "$content" | grep -q "networking"; then
                echo "Network configuration and management"
            elif echo "$content" | grep -q "storage"; then
                echo "Storage and filesystem configuration"
            elif echo "$content" | grep -q "security"; then
                echo "Security tools and hardening configuration"
            elif echo "$content" | grep -q "development"; then
                echo "Development tools and environment configuration"
            elif echo "$content" | grep -q "packages"; then
                echo "System and user package configuration"
            elif echo "$content" | grep -q "fonts"; then
                echo "Font configuration and management"
            elif echo "$content" | grep -q "git"; then
                echo "Git version control configuration"
            elif echo "$content" | grep -q "shell\|zsh\|bash\|fish"; then
                echo "Shell environment and configuration"
            elif echo "$content" | grep -q "home\."; then
                echo "Home Manager user environment configuration"
            else
                # Generate from filename
                echo "$name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g' | sed 's/$/ configuration/'
            fi
            ;;
    esac
}

# Function to detect dependencies
detect_dependencies() {
    local file="$1"
    local deps=""
    
    # Check for explicit imports
    if grep -q "imports = \[" "$file" 2>/dev/null; then
        deps=$(grep -A5 "imports = \[" "$file" | grep -oE "inputs\.[^]]*" | head -3 | tr '\n' ', ' | sed 's/, $//')
    fi
    
    # Check for references to other modules
    if grep -q "config\.flake\.modules\." "$file" 2>/dev/null; then
        local refs=$(grep -oE "config\.flake\.modules\.[^;]*" "$file" | head -3 | tr '\n' ', ' | sed 's/, $//')
        if [ -n "$refs" ]; then
            if [ -n "$deps" ]; then
                deps="$deps, $refs"
            else
                deps="$refs"
            fi
        fi
    fi
    
    echo "$deps"
}

# Function to determine pattern type
determine_pattern() {
    local file="$1"
    local namespace="$2"
    local name=$(basename "$file" .nix)
    
    case "$namespace" in
        nixos.nvidia-gpu|nixos.efi|nixos.swap)
            echo "Named module - Optional feature that can be imported when needed"
            ;;
        nixos.base)
            echo "Base system configuration - Required by all NixOS systems"
            ;;
        nixos.pc)
            echo "Personal computer configuration - Extends base for desktop systems"
            ;;
        nixos.workstation)
            echo "Workstation configuration - Extends pc for development systems"
            ;;
        configurations*)
            echo "Host configuration - System-specific settings and hardware"
            ;;
        homeManager.base)
            echo "Home Manager base - CLI and terminal environment"
            ;;
        homeManager.gui)
            echo "Home Manager GUI - Graphical application configuration"
            ;;
        meta)
            echo "Metadata configuration - System-wide settings and values"
            ;;
        perSystem)
            echo "Per-system configuration - Architecture-specific packages and tools"
            ;;
        nixos.boot)
            echo "Boot configuration - System initialization and bootloader"
            ;;
        nixos.style)
            echo "Styling configuration - System-wide theming and appearance"
            ;;
        *)
            # Analyze content for pattern
            if grep -q "hardware\|driver" "$file" 2>/dev/null; then
                echo "Hardware configuration module"
            elif grep -q "service\|daemon" "$file" 2>/dev/null; then
                echo "System service configuration"
            elif grep -q "package\|program" "$file" 2>/dev/null; then
                echo "Package and program configuration"
            else
                echo "System configuration module"
            fi
            ;;
    esac
}

# Process each module
count=0
updated=0
skipped=0
failed=0

while IFS= read -r -d '' file; do
    count=$((count + 1))
    
    # Check if header already exists
    if grep -q "^# Module:" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $(basename "$file") - already has header"
        skipped=$((skipped + 1))
        continue
    fi
    
    # Extract information
    rel_path=$(echo "$file" | sed 's|modules/||')
    namespace=$(extract_namespace "$file")
    purpose=$(determine_purpose "$file")
    pattern=$(determine_pattern "$file" "$namespace")
    deps=$(detect_dependencies "$file")
    
    # Build header
    header="# Module: $rel_path
# Purpose: $purpose
# Namespace: flake.modules.$namespace
# Pattern: $pattern"
    
    # Add dependencies if found
    if [ -n "$deps" ]; then
        header="$header
# Dependencies: $deps"
    fi
    
    # Add notes for special modules
    case "$(basename "$file" .nix)" in
        nvidia-gpu)
            header="$header
# Note: Requires NVIDIA hardware - use specialisation for conditional activation"
            ;;
        efi)
            header="$header
# Note: Only for UEFI systems - not needed for BIOS/legacy boot"
            ;;
        swap)
            header="$header
# Note: Optional - only import if swap space is desired"
            ;;
    esac
    
    # Create temporary file with header
    {
        echo "$header"
        echo ""
        cat "$file"
    } > "$file.tmp"
    
    # Replace original file
    mv "$file.tmp" "$file"
    
    echo -e "${YELLOW}+${NC} Added header to: $rel_path"
    echo -e "  ${BLUE}Namespace:${NC} $namespace"
    echo -e "  ${BLUE}Pattern:${NC} $pattern"
    if [ -n "$deps" ]; then
        echo -e "  ${BLUE}Dependencies:${NC} $deps"
    fi
    updated=$((updated + 1))
    
done < <(find modules -name "*.nix" -print0)

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Total modules processed: ${count}"
echo -e "${GREEN}Already had headers: ${skipped}${NC}"
echo -e "${YELLOW}Headers added: ${updated}${NC}"
if [ $failed -gt 0 ]; then
    echo -e "${RED}Failed: ${failed}${NC}"
fi
echo ""
echo -e "${GREEN}✅ Module headers analysis complete!${NC}"
echo -e "Backup saved at: ${backup_dir}"
echo ""
echo -e "${YELLOW}⚠ IMPORTANT:${NC} Review the headers and manually adjust any that need refinement."
echo -e "Focus especially on:"
echo -e "  - Named modules (nvidia-gpu, efi, swap)"
echo -e "  - Host configurations"
echo -e "  - Modules with complex dependencies"