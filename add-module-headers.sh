#!/usr/bin/env bash
# Script to add standardized headers to all Nix modules
# Part of Phase 3 of Dendritic Pattern remediation

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Adding Standardized Module Headers ===${NC}"
echo ""

# Backup modules directory first
backup_dir="modules.backup.headers.$(date +%Y%m%d-%H%M%S)"
echo -e "${YELLOW}Creating backup at: $backup_dir${NC}"
cp -r modules/ "$backup_dir/"

count=0
updated=0
skipped=0

# Process all .nix files recursively
while IFS= read -r -d '' file; do
    count=$((count + 1))
    
    # Check if header already exists
    if grep -q "^# Module:" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $(basename "$file") - already has header"
        skipped=$((skipped + 1))
        continue
    fi
    
    # Extract information for header
    rel_path=$(echo "$file" | sed 's|modules/||')
    dir=$(dirname "$rel_path")
    name=$(basename "$file" .nix)
    
    # Detect namespace and pattern from file content
    namespace="unknown"
    pattern="Module configuration"
    
    # Check various namespace patterns
    if grep -q "flake\.modules\.nixos\.base" "$file" 2>/dev/null; then
        namespace="nixos.base"
        pattern="Base system configuration"
    elif grep -q "flake\.modules\.nixos\.pc" "$file" 2>/dev/null; then
        namespace="nixos.pc"
        pattern="Personal computer configuration"
    elif grep -q "flake\.modules\.nixos\.workstation" "$file" 2>/dev/null; then
        namespace="nixos.workstation"
        pattern="Workstation configuration"
    elif grep -q 'flake\.modules\.nixos\."[^"]*"' "$file" 2>/dev/null; then
        namespace=$(grep -oP 'flake\.modules\.nixos\."\K[^"]+' "$file" 2>/dev/null | head -1 || echo "nixos.named")
        pattern="Named module"
    elif grep -q "configurations\.nixos\." "$file" 2>/dev/null; then
        namespace="configurations"
        pattern="Host configuration"
    elif grep -q "flake\.modules\.homeManager\.base" "$file" 2>/dev/null; then
        namespace="homeManager.base"
        pattern="Home Manager base configuration"
    elif grep -q "flake\.modules\.homeManager\.gui" "$file" 2>/dev/null; then
        namespace="homeManager.gui"
        pattern="Home Manager GUI configuration"
    elif grep -q "perSystem" "$file" 2>/dev/null; then
        namespace="perSystem"
        pattern="Per-system configuration"
    elif grep -q "flake\.meta" "$file" 2>/dev/null; then
        namespace="meta"
        pattern="Metadata configuration"
    fi
    
    # Generate human-readable purpose from filename
    purpose=$(echo "$name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
    
    # Handle special cases for better descriptions
    case "$name" in
        *-nix) purpose="${purpose% Nix} Nix configuration" ;;
        *-nixos) purpose="${purpose% Nixos} NixOS configuration" ;;
        *-manager) purpose="${purpose} configuration" ;;
        efi) purpose="EFI boot support" ;;
        swap) purpose="Swap space configuration" ;;
        tmp) purpose="Temporary filesystem configuration" ;;
    esac
    
    # Create temporary file with header
    cat > "$file.tmp" << EOF
# Module: $rel_path
# Purpose: $purpose
# Namespace: flake.modules.$namespace
# Pattern: $pattern

EOF
    
    # Append original content
    cat "$file" >> "$file.tmp"
    
    # Replace original file
    mv "$file.tmp" "$file"
    
    echo -e "${YELLOW}+${NC} Added header to: $rel_path"
    updated=$((updated + 1))
    
done < <(find modules -name "*.nix" -print0)

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Total modules processed: ${count}"
echo -e "${GREEN}Already had headers: ${skipped}${NC}"
echo -e "${YELLOW}Headers added: ${updated}${NC}"
echo ""
echo -e "${GREEN}✅ Module headers standardization complete!${NC}"
echo -e "Backup saved at: ${backup_dir}"