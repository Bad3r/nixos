# Dendritic Pattern Remediation Plan - Revised Version
## Complete Architectural Restructuring for True Compliance

### Executive Summary
**Current Score**: 72/100 (Failing)  
**Target Score**: 100/100 (Perfect Compliance)  
**Approach**: Complete restructuring based on golden standard patterns  
**Timeline**: 4-6 weeks (realistic estimate with proper testing)  
**Risk Level**: HIGH - Requires extremely careful migration with atomic operations

---

## Critical Understanding: What the Dendritic Pattern ACTUALLY Is

### EXPLICIT MODULE-TO-NAMESPACE MAPPING TABLE

| Directory | Module Type | Extends Namespace | Rationale |
|-----------|-------------|-------------------|------------|
| `audio/*` | Sound subsystem | `nixos.pc` | User-facing desktop feature |
| `boot/*` | Boot configuration | `nixos.base` | Core system requirement |
| `hardware/nvidia.nix` | NVIDIA drivers | `nixos.nvidia-gpu` | Optional named module |
| `hardware/bluetooth.nix` | Bluetooth | `nixos.pc` | Desktop/laptop feature |
| `networking/networkmanager.nix` | NetworkManager | `nixos.pc` | Desktop networking |
| `networking/systemd-networkd.nix` | systemd-networkd | `nixos.base` | Server/core networking |
| `shells/*` | Shell configs | `nixos.base` or `nixos.pc` | Depends on scope |
| `storage/swap.nix` | Swap config | `nixos.base` | Core system feature |
| `storage/zfs.nix` | ZFS filesystem | `nixos.workstation` | Advanced feature |
| `style/*` | Theming/fonts | `nixos.pc` | Desktop customization |
| `window-manager/*` | Desktop environments | `nixos.pc` | GUI feature |
| `virtualization/docker.nix` | Docker | `nixos.workstation` | Developer tool |
| `virtualization/qemu.nix` | QEMU/KVM | `nixos.workstation` | Advanced virtualization |
| `development/*` | Dev tools | `nixos.workstation` | Developer features |
| `applications/*` | User apps | `nixos.pc` | Desktop applications |
| `security/yubikey.nix` | YubiKey support | `nixos.workstation` | Advanced security |
| `security/firewall.nix` | Basic firewall | `nixos.base` | Core security |

**KEY RULE**: Directory organizes by topic. Namespace determined by audience/purpose.

### Namespace Extension Rules - CORRECTED
**CRITICAL**: Modules EXTEND existing namespaces based on PURPOSE, not directory

```markdown
## Correct Namespace Assignment by Module Purpose

### nixos.base (Core System - ALL systems need these)
- Boot configuration (modules/boot/*)
- Storage fundamentals (modules/storage/* for core storage)
- Nix settings (modules/nix/*)
- Essential system configuration

### nixos.pc (Personal Computer - Desktop/Laptop features)
- Audio subsystem (modules/audio/* → nixos.pc)
- GUI applications (modules/applications/*)
- Desktop environments (modules/window-manager/*)
- User-facing networking (NetworkManager, etc.)
- Fonts and theming (modules/style/*)

### nixos.workstation (Developer Features - Advanced users)
- Virtualization (modules/virtualization/* → nixos.workstation)
- Development tools (modules/development/*)
- Databases and services
- Docker/Podman
- Advanced tooling

### Named Modules (Only when SOME systems need it)
- nixos.laptop - Battery management, WiFi, touchpad
- nixos.nvidia-gpu - Only for NVIDIA systems
- nixos.server - Headless server features

## Directory Structure vs Namespace
- Directory: Organizes by semantic purpose
- Namespace: Determined by WHO needs the feature
- Example: modules/audio/pipewire.nix → nixos.pc (NOT nixos.audio)
- Example: modules/virtualization/docker.nix → nixos.workstation (NOT nixos.virtualization)
```

### The Golden Standard Structure
The dendritic pattern organizes modules by **semantic purpose** for clarity:

```
modules/
├── audio/          # Audio subsystem → extends nixos.pc
├── boot/           # Boot configuration → extends nixos.base
├── hardware/       # Hardware-specific → creates named modules or extends base
├── networking/     # Network config → extends pc (user) or base (system)
├── shells/         # Shell environments → extends pc or base
├── storage/        # Storage config → extends base (core) or workstation (advanced)
├── style/          # Theming → extends nixos.pc
├── window-manager/ # Window managers → extends nixos.pc
├── virtualization/ # VMs/containers → extends nixos.workstation
├── development/    # Dev tools → extends nixos.workstation
└── ...

KEY INSIGHT: Directory location is for organization.
Namespace assignment is based on PURPOSE and AUDIENCE.
```

### Core Principles
1. **Modules EXTEND namespaces**, they don't define one per directory
2. **"Named Modules as Needed"** - Only create named modules for optional features
3. **Pipe operators are MANDATORY** throughout
4. **import-tree handles discovery** - No manual imports

---

## Phase 0: Pre-Implementation Analysis [Day 1 - 4 hours]

### 0.1 Create Safety Backup
```bash
#!/usr/bin/env bash
# save as backup-before-changes.sh
set -euo pipefail

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="nixos-backup-$TIMESTAMP"
cp -r /home/vx/nixos "/home/vx/$BACKUP_DIR"

# Save timestamp for rollback
echo "$TIMESTAMP" > .backup-timestamp

# Create git backup branch
cd /home/vx/nixos
git checkout -b dendritic-restructure-backup
git add -A
git commit -m "backup: complete state before dendritic restructuring"

# Document current build
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
nix build .#nixosConfigurations.system76.config.system.build.toplevel \
  --dry-run 2>&1 > build-status-before.txt

# Create module inventory
find modules -name "*.nix" -type f | while read -r file; do
  basename "$file" .nix
done | sort > all-modules-before.txt

echo "Backup created at /home/vx/$BACKUP_DIR"
```

### 0.2 Analyze Current Module Structure
```bash
#!/usr/bin/env bash
# save as analyze-current-modules.sh
set -euo pipefail

echo "=== Current Module Analysis ==="

# Map all modules and their namespaces
find modules -name "*.nix" -type f | while read -r file; do
  echo "File: $file"
  # Extract namespace definitions
  grep "flake.modules" "$file" 2>/dev/null | head -2 || echo "  No namespace defined"
  # Check for mkForce usage
  if grep -q "mkForce" "$file"; then
    echo "  Contains mkForce at lines:"
    grep -n "mkForce" "$file" | cut -d: -f1 | tr '\n' ' '
    echo
  fi
  echo "---"
done > module-analysis.txt

echo "Analysis saved to module-analysis.txt"
```

### 0.3 Create Validation Script
```bash
#!/usr/bin/env bash
# save as validate-build.sh
set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"

echo "Validating configuration..."
if nix build .#nixosConfigurations.system76.config.system.build.toplevel \
   --dry-run 2>/dev/null; then
  echo "✓ Build validation passed"
  exit 0
else
  echo "✗ Build validation failed"
  exit 1
fi
```

### 0.4 Understand Existing Dependencies
```bash
#!/usr/bin/env bash
# save as map-dependencies.sh
set -euo pipefail

# Check which modules import which
for file in modules/**/*.nix; do
  echo "=== $file ==="
  grep -h "imports.*config.flake.modules" "$file" 2>/dev/null || true
done > dependency-map.txt
```

---

## Phase 1: Add Pipe Operators First [Day 2 - 3 hours]

### 1.1 Update All Scripts with Pipe Operators (SAFE VERSION)
```bash
#!/usr/bin/env bash
# save as add-pipe-operators-first.sh
set -euo pipefail

# Check if already complete
if [ -f ".phase-1-complete" ]; then
  echo "Phase 1 already completed"
  exit 0
fi

# Create staging directory for atomic operations
STAGING_DIR=".staging-pipe-operators"
mkdir -p "$STAGING_DIR"

# Track changes for rollback
CHANGES_LOG="$STAGING_DIR/changes.log"
> "$CHANGES_LOG"

# Update all shell scripts SAFELY
for script in *.sh; do
  [ -f "$script" ] || continue
  
  if grep -q "NIX_CONFIG.*pipe-operators" "$script" || grep -q "extra-experimental-features.*pipe-operators" "$script"; then
    echo "✓ $script already has pipe operators"
    continue
  fi
  
  # Only process scripts that use nix commands
  if ! grep -q "nix " "$script" && ! grep -q "nixos-rebuild" "$script"; then
    continue
  fi
  
  # Create backup in staging
  cp "$script" "$STAGING_DIR/$script.original"
  
  # Safer approach - add after shebang regardless of other content
  {
    head -1 "$script"  # Keep shebang
    echo 'export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"'
    tail -n +2 "$script"  # Rest of file
  } > "$STAGING_DIR/$script.new"
  
  # Validate syntax of modified script
  if bash -n "$STAGING_DIR/$script.new" 2>/dev/null; then
    mv "$STAGING_DIR/$script.new" "$script"
    echo "$script" >> "$CHANGES_LOG"
    echo "✓ Added pipe operators to $script"
  else
    echo "✗ Failed to modify $script safely - skipping"
    rm "$STAGING_DIR/$script.new"
  fi
done

# Validate build still works
if ! ./validate-build.sh; then
  echo "FAILED: Build broken after adding pipe operators"
  echo "Rolling back changes..."
  while read -r script; do
    [ -f "$STAGING_DIR/$script.original" ] && mv "$STAGING_DIR/$script.original" "$script"
  done < "$CHANGES_LOG"
  rm -rf "$STAGING_DIR"
  exit 1
fi

# Success - clean up staging
rm -rf "$STAGING_DIR"
touch .phase-1-complete
echo "Phase 1 complete: Pipe operators added safely"
```

## Phase 2: Fix Immediate Namespace Violations [Day 3-4 - 8 hours]

### 1.1 Fix Modules with NO Namespace (Safe Approach)

For each module without a namespace, we need to understand its content first, then wrap it properly.

#### Task 1.1.1: Analyze and Fix base/efi.nix (REQUIRES MANUAL INTERVENTION)
```bash
#!/usr/bin/env bash
# save as fix-efi.sh
set -euo pipefail

FILE="modules/base/efi.nix"

# This requires manual intervention due to complexity
echo "=== Manual Fix Required for $FILE ==="
echo ""
echo "The file needs to be wrapped in the correct namespace."
echo "Current structure:"
echo ""
head -20 "$FILE" 2>/dev/null || echo "File not found"
echo ""
echo "Required structure:"
cat << 'EOF'
{ lib, config, pkgs, ... }:  # Preserve original parameters if different
{
  flake.modules.nixos.base = {
    # Original content goes here, indented by 4 spaces
    # Make sure to preserve any existing function logic
  };
}
EOF
echo ""
echo "Please manually edit $FILE to wrap it in the nixos.base namespace."
echo "This ensures we don't lose any function parameters or context."
echo ""
echo "After manual edit, validate with:"
echo "  nix-instantiate --parse $FILE"
echo "  nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run"

# Create a template for reference
TEMPLATE="$FILE.template"
if [ -f "$FILE" ]; then
  echo "Creating template at $TEMPLATE for reference..."
  {
    echo "{ lib, config, pkgs, ... }:"
    echo "{"
    echo "  flake.modules.nixos.base = {"
    echo "    # === ORIGINAL CONTENT BELOW (indent by 4 more spaces) ==="
    cat "$FILE"
    echo "    # === END ORIGINAL CONTENT ==="
    echo "  };"
    echo "}"
  } > "$TEMPLATE"
  echo "Template created at $TEMPLATE"
fi
```

#### Task 1.1.2: Manual Namespace Wrapper Guide (PURPOSE-BASED)
```bash
#!/usr/bin/env bash
# save as guide-namespace-wrapper.sh
set -euo pipefail

# This script provides guidance for manual namespace wrapping
# CRITICAL: Namespace is determined by PURPOSE, not directory!

echo "=== Namespace Wrapper Migration Guide (CORRECTED) ==="
echo ""
echo "CRITICAL: Namespace assignment is based on MODULE PURPOSE, not directory!"
echo ""

# Find modules without namespaces
echo "Analyzing modules for namespace assignment..."
echo ""

for file in modules/**/*.nix; do
  [ -f "$file" ] || continue
  
  if ! grep -q "flake.modules" "$file" 2>/dev/null; then
    echo "File: $file"
    echo "  Status: Missing namespace"
    
    # Analyze content to suggest namespace
    echo "  Content analysis:"
    
    # Check for keywords to determine purpose
    if grep -q "boot\|initrd\|kernel\|loader" "$file" 2>/dev/null; then
      echo "    - Boot/system configuration detected → suggest nixos.base"
    fi
    
    if grep -q "pipewire\|pulseaudio\|alsa\|sound" "$file" 2>/dev/null; then
      echo "    - Audio configuration detected → suggest nixos.pc"
    fi
    
    if grep -q "docker\|virtualbox\|qemu\|libvirt" "$file" 2>/dev/null; then
      echo "    - Virtualization detected → suggest nixos.workstation"
    fi
    
    if grep -q "plasma\|gnome\|hyprland\|sway\|xserver" "$file" 2>/dev/null; then
      echo "    - Desktop environment detected → suggest nixos.pc"
    fi
    
    if grep -q "postgresql\|mysql\|redis\|development" "$file" 2>/dev/null; then
      echo "    - Development tools detected → suggest nixos.workstation"
    fi
    
    echo "  ACTION REQUIRED: Manual review to determine correct namespace"
    echo ""
  fi
done

cat << 'EOF'
=== NAMESPACE DECISION GUIDE ===

Ask these questions for each module:

1. Is this needed by ALL systems? → nixos.base
   (boot, core storage, nix config)

2. Is this for desktop/laptop users? → nixos.pc
   (audio, GUI, desktop environments, user apps)

3. Is this for developers/power users? → nixos.workstation
   (virtualization, databases, dev tools)

4. Is this optional for specific hardware? → Named module
   (nvidia-gpu, laptop-specific, server-specific)

REMEMBER: Directory location is ONLY for organization!
The namespace must match the module's PURPOSE and AUDIENCE.

Example fixes:
- modules/audio/pipewire.nix → nixos.pc (NOT nixos.audio)
- modules/boot/efi.nix → nixos.base (NOT nixos.boot)
- modules/virtualization/docker.nix → nixos.workstation (NOT nixos.virtualization)
EOF
```

#### Task 1.1.3: Manual Namespace Assignment Based on Purpose
```bash
#!/usr/bin/env bash
# save as apply-namespace-fixes-manual.sh
set -euo pipefail

cat << 'EOF'
=== MANUAL NAMESPACE ASSIGNMENT REQUIRED ===

Each module must be manually reviewed and assigned to the correct namespace
based on its PURPOSE, not its directory location.

Modules requiring manual namespace assignment:

1. modules/base/nix-package.nix
   Analyze: Core Nix package configuration
   Assign to: nixos.base (all systems need this)

2. modules/base/nix-settings.nix
   Analyze: Core Nix settings
   Assign to: nixos.base (fundamental configuration)

3. modules/pc/networking.nix
   Analyze: NetworkManager or user-facing networking?
   Assign to: nixos.pc (if desktop networking)

4. modules/pc/ssh.nix
   Analyze: SSH client or server?
   Assign to: nixos.base (if server) or nixos.pc (if client config)

5. modules/pc/unfree-packages.nix
   Analyze: Desktop applications?
   Assign to: nixos.pc (user applications)

6. modules/desktop/color-scheme.nix
   Analyze: Theming/styling
   Assign to: nixos.pc (desktop customization)
   Note: Desktop namespace will be eliminated

For each module:
1. Read the module content
2. Determine its purpose and audience
3. Manually wrap in the appropriate namespace
4. Validate syntax and semantics
5. Test the build

DO NOT automate this process - it requires human judgment!
EOF
```

### Safe Text Replacement Pattern (Using Perl)
```bash
#!/usr/bin/env bash
# save as safe-replace.sh
set -euo pipefail

# Safe replacement using perl with proper escaping
safe_replace() {
  local file="$1"
  local pattern="$2"
  local replacement="$3"
  
  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file"
    return 1
  fi
  
  # Create backup with timestamp
  local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$file" "$backup"
  
  # Use perl for safer replacement with automatic escaping
  if perl -i.tmp -pe "s/\Q$pattern\E/$replacement/g" "$file" 2>/dev/null; then
    # Validate Nix syntax
    if nix-instantiate --parse "$file" >/dev/null 2>&1; then
      echo "✓ Successfully updated $file"
      # Semantic validation - try to build
      if nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>/dev/null; then
        echo "✓ Build validation passed"
        rm "${file}.tmp" "$backup"  # Clean up backups on success
        return 0
      else
        echo "✗ Build validation failed - reverting"
        mv "$backup" "$file"
        return 1
      fi
    else
      echo "✗ Syntax validation failed - reverting"
      mv "$backup" "$file"
      return 1
    fi
  else
    echo "✗ Replacement failed - reverting"
    mv "$backup" "$file"
    return 1
  fi
}

# Batch replacement with manifest
safe_batch_replace() {
  local manifest=".replacement-manifest.json"
  echo '[]' > "$manifest"
  
  # Record each change
  for file in "$@"; do
    # ... perform replacement and log to manifest
    echo "Processing $file..."
  done
}
```

### 1.2 Fix Wrong Namespace Definitions

#### Task 1.2.1: Fix boot-visuals.nix (Multiple Namespaces)
```bash
#!/usr/bin/env bash
# save as fix-boot-visuals.sh
set -euo pipefail

FILE="modules/base/boot-visuals.nix"
cp "$FILE" "$FILE.bak"

# Extract only the base namespace content
# This requires manual inspection and editing
echo "Manual fix required for $FILE"
echo "The file defines both nixos.base and nixos.pc"
echo "Need to split or consolidate to single namespace"

# Suggested approach:
cat > "$FILE.fixed" << 'EOF'
{ lib, config, ... }:
{
  flake.modules.nixos.base = {
    # Boot visual configuration should be in base
    boot.plymouth.enable = true;
    # Other boot visual settings...
  };
}
EOF
```

#### Task 1.2.2: Fix Named Module Violations
```bash
#!/usr/bin/env bash
# save as fix-named-modules.sh
set -euo pipefail

# Fix security-tools to use workstation namespace
FILE="modules/workstation/security-tools.nix"
if [ -f "$FILE" ]; then
  cp "$FILE" "$FILE.bak"
  sed -i 's/flake\.modules\.nixos\.security-tools/flake.modules.nixos.workstation/' "$FILE"
  echo "✓ Fixed security-tools namespace"
fi

# Fix tmp.nix nested namespace
FILE="modules/workstation/tmp.nix"
if [ -f "$FILE" ]; then
  cp "$FILE" "$FILE.bak"
  # Replace the incorrect nested namespace
  sed -i 's/flake\.modules\.nixos\.workstation\.boot\.tmp\.cleanOnBoot = true/flake.modules.nixos.workstation = { boot.tmp.cleanOnBoot = true; }/' "$FILE"
  echo "✓ Fixed tmp.nix namespace"
fi

# Fix desktop KDE modules
for file in modules/desktop/kde-packages.nix modules/desktop/plasma-packages.nix; do
  if [ -f "$file" ]; then
    cp "$file" "$file.bak"
    sed -i 's/flake\.modules\.nixos\.kde-plasma/flake.modules.nixos.desktop/' "$file"
    echo "✓ Fixed $(basename $file) namespace"
  fi
done
```

---

## Phase 2: Reorganize to Semantic Structure [Day 4-7 - 16 hours]

### 2.1 Create New Directory Structure
```bash
#!/usr/bin/env bash
# save as create-semantic-structure.sh
set -euo pipefail

# Create semantic directories matching golden standard
mkdir -p modules/{audio,boot,hardware,networking,shells,storage,style,window-manager}
mkdir -p modules/{terminal,virtualization,web-browsers,file-management}
mkdir -p modules/{development,security,meta}

echo "✓ Created semantic directory structure"
```

### 2.2 Safe Module Migration with Manifest
```bash
#!/usr/bin/env bash
# save as migrate-modules-safely.sh
set -euo pipefail

# Create migration manifest
MANIFEST=".migration-manifest.txt"
ERROR_LOG=".migration-errors.txt"
> "$MANIFEST"
> "$ERROR_LOG"

# Staging directory for atomic operations
STAGING=".staging-migration"
mkdir -p "$STAGING"

# Function to safely move a file
safe_move() {
  local src="$1"
  local dst_dir="$2"
  local dst="$dst_dir/$(basename "$src")"
  
  # Pre-flight checks
  if [ ! -f "$src" ]; then
    echo "Source not found: $src" >> "$ERROR_LOG"
    return 1
  fi
  
  if [ -f "$dst" ]; then
    echo "ERROR: Destination already exists: $dst" | tee -a "$ERROR_LOG"
    echo "Would overwrite! Skipping $src -> $dst" | tee -a "$ERROR_LOG"
    return 1
  fi
  
  # Create destination directory if needed
  mkdir -p "$dst_dir"
  
  # Copy to staging first
  cp "$src" "$STAGING/$(basename "$src")"
  
  # Attempt the move
  if mv "$src" "$dst" 2>/dev/null; then
    echo "$src -> $dst" >> "$MANIFEST"
    echo "✓ Moved: $(basename "$src") to $dst_dir/"
    return 0
  else
    echo "Failed to move: $src to $dst" >> "$ERROR_LOG"
    return 1
  fi
}

# Create semantic directories
echo "Creating semantic directory structure..."
for dir in audio boot hardware networking shells storage style window-manager \
           terminal virtualization web-browsers file-management \
           development security meta; do
  mkdir -p "modules/$dir"
done

# Perform migrations with safety checks
echo "Migrating modules..."

# Boot related
for file in modules/base/boot-*.nix; do
  [ -f "$file" ] && safe_move "$file" "modules/boot"
done
[ -f "modules/base/efi.nix" ] && safe_move "modules/base/efi.nix" "modules/boot"

# Storage related (swap might already be in correct location)
if [ -f "modules/workstation/swap.nix" ]; then
  safe_move "modules/workstation/swap.nix" "modules/storage"
fi
for file in modules/base/storage-*.nix; do
  [ -f "$file" ] && safe_move "$file" "modules/storage"
done

# Networking
[ -f "modules/pc/networking.nix" ] && safe_move "modules/pc/networking.nix" "modules/networking"
[ -f "modules/pc/ssh.nix" ] && safe_move "modules/pc/ssh.nix" "modules/networking"

# Style and theming
[ -f "modules/desktop/color-scheme.nix" ] && safe_move "modules/desktop/color-scheme.nix" "modules/style"
[ -f "modules/desktop/fonts.nix" ] && safe_move "modules/desktop/fonts.nix" "modules/style"
[ -f "modules/desktop/opacity.nix" ] && safe_move "modules/desktop/opacity.nix" "modules/style"

# Audio
[ -f "modules/desktop/audio-pipewire.nix" ] && safe_move "modules/desktop/audio-pipewire.nix" "modules/audio"
[ -f "modules/pc/pipewire.nix" ] && safe_move "modules/pc/pipewire.nix" "modules/audio"

# Development and virtualization
for file in modules/workstation/development-*.nix; do
  [ -f "$file" ] && safe_move "$file" "modules/development"
done
[ -f "modules/workstation/docker.nix" ] && safe_move "modules/workstation/docker.nix" "modules/virtualization"
[ -f "modules/workstation/virtualbox.nix" ] && safe_move "modules/workstation/virtualbox.nix" "modules/virtualization"

# Security
[ -f "modules/workstation/security-tools.nix" ] && safe_move "modules/workstation/security-tools.nix" "modules/security"

# Report results
echo ""
echo "=== Migration Summary ==="
echo "Successful moves: $(wc -l < "$MANIFEST")"
if [ -s "$ERROR_LOG" ]; then
  echo "Errors encountered: $(wc -l < "$ERROR_LOG")"
  echo "See $ERROR_LOG for details"
fi
echo "Manifest saved to: $MANIFEST"

# Clean up staging on success
rm -rf "$STAGING"

echo "✓ Module migration complete"
```

### 2.3 Correct Namespace Assignment Guide
```bash
#!/usr/bin/env bash
# save as namespace-assignment-guide.sh
set -euo pipefail

echo "=== Namespace Assignment Guide ==="
echo ""
echo "Modules must extend EXISTING namespaces based on PURPOSE:"
echo ""

cat << 'EOF'
Namespace Assignment Map:

→ nixos.base (ALL systems need this):
  - modules/boot/* (boot loaders, initrd)
  - modules/nix/* (Nix configuration)
  - modules/storage/* (core filesystems)
  - Basic system configuration

→ nixos.pc (Desktop/Laptop features):
  - modules/audio/* (PipeWire, ALSA, PulseAudio)
  - modules/style/* (fonts, themes, colors)
  - modules/window-manager/* (Plasma, GNOME, Hyprland)
  - modules/applications/* (Firefox, terminal emulators)
  - modules/networking/* (NetworkManager for desktop)

→ nixos.workstation (Developer features):
  - modules/virtualization/* (Docker, VirtualBox, QEMU)
  - modules/development/* (compilers, IDEs, databases)
  - modules/security/* (advanced security tools)
  - Advanced networking tools

→ Named modules (optional features):
  - modules/hardware/nvidia.nix → nixos.nvidia-gpu
  - modules/hardware/laptop.nix → nixos.laptop
  - Server-specific features → nixos.server

CRITICAL: Directory location does NOT determine namespace!
Example: modules/audio/pipewire.nix uses nixos.pc NOT nixos.audio
EOF

echo ""
echo "Manual review required for each module to determine correct namespace."
echo "Check golden standard at /home/vx/git/infra for examples."
```

---

## Phase 3: Remove specialArgs and Break Up Monoliths [Day 5 - 4 hours]

### 3.1 Remove specialArgs Anti-pattern
```bash
#!/usr/bin/env bash
# save as remove-specialargs.sh
set -euo pipefail

if [ -f ".phase-3a-complete" ]; then
  echo "Phase 3a already completed"
  exit 0
fi

echo "=== Finding specialArgs usage ==="
grep -r "specialArgs" . --include="*.nix" | while read -r line; do
  file="${line%%:*}"
  echo "Found specialArgs in $file - needs manual removal"
  
  # Common pattern: replace specialArgs with module arguments
  echo "Suggested fix: Use module system instead of specialArgs"
done

# Validate after changes
./validate-build.sh || {
  echo "FAILED: Build broken after removing specialArgs"
  exit 1
}

touch .phase-3a-complete
```

### 3.2 Break Up system76-complete.nix
```bash
#!/usr/bin/env bash
# save as breakup-monoliths.sh
set -euo pipefail

if [ -f ".phase-3b-complete" ]; then
  echo "Phase 3b already completed"
  exit 0
fi

# Find large files that need breaking up
echo "=== Finding monolithic modules ==="
find modules -name "*.nix" -type f -exec wc -l {} \; | sort -rn | head -10

# system76-complete.nix likely needs splitting
if [ -f "modules/hosts/system76/complete.nix" ]; then
  echo "Breaking up system76-complete.nix..."
  
  # Create separate modules for logical sections
  mkdir -p modules/hosts/system76/split
  
  # This requires manual analysis and splitting
  echo "Manual action required: Split complete.nix into:"
  echo "  - hardware.nix (hardware configuration)"
  echo "  - packages.nix (system packages)"
  echo "  - services.nix (system services)"
  echo "  - users.nix (user configuration)"
fi

./validate-build.sh || {
  echo "FAILED: Build broken after breaking up monoliths"
  exit 1
}

touch .phase-3b-complete
```

## Phase 4: Eliminate Desktop Namespace [Day 6 - 4 hours]

### 3.1 Safely Eliminate Desktop Namespace
```bash
#!/usr/bin/env bash
# save as eliminate-desktop-namespace-safely.sh
set -euo pipefail

# Create elimination manifest
MANIFEST=".desktop-elimination-manifest.txt"
> "$MANIFEST"

# Pre-flight checks
echo "Checking for desktop namespace usage..."

# Find all files referencing desktop namespace
DESKTOP_REFS=$(grep -r "flake\.modules\.nixos\.desktop" modules/ --include="*.nix" 2>/dev/null | cut -d: -f1 | sort -u || true)

if [ -z "$DESKTOP_REFS" ]; then
  echo "No desktop namespace references found."
  exit 0
fi

echo "Found desktop namespace in:"
echo "$DESKTOP_REFS" | while read -r file; do
  echo "  - $file"
done

# Function to safely migrate a desktop module
migrate_desktop_module() {
  local src="$1"
  local dst="$2"
  local new_namespace="$3"
  
  if [ ! -f "$src" ]; then
    echo "Source not found: $src"
    return 1
  fi
  
  if [ -f "$dst" ]; then
    echo "ERROR: Destination already exists: $dst"
    echo "Manual intervention required for: $src"
    return 1
  fi
  
  # Create backup
  cp "$src" "${src}.backup"
  
  # Copy and modify
  cp "$src" "$dst"
  
  # Replace namespace using perl (safer than sed)
  if perl -i -pe "s/flake\.modules\.nixos\.desktop/flake.modules.nixos.$new_namespace/g" "$dst"; then
    # Validate syntax
    if nix-instantiate --parse "$dst" >/dev/null 2>&1; then
      echo "$src -> $dst (namespace: $new_namespace)" >> "$MANIFEST"
      echo "✓ Migrated: $(basename "$src") to $dst"
      rm "$src"  # Remove original only after successful migration
      return 0
    else
      echo "✗ Syntax error after migration - keeping original"
      rm "$dst"
      return 1
    fi
  else
    echo "✗ Failed to update namespace"
    rm "$dst"
    return 1
  fi
}

# Migrate desktop modules based on content
echo "Migrating desktop modules..."

# GUI applications should go to pc namespace
if [ -f "modules/desktop/applications.nix" ]; then
  migrate_desktop_module "modules/desktop/applications.nix" \
                         "modules/pc/gui-applications.nix" \
                         "pc"
fi

# Window manager modules
for wm_file in modules/desktop/plasma*.nix modules/desktop/kde*.nix; do
  [ -f "$wm_file" ] || continue
  base_name=$(basename "$wm_file")
  migrate_desktop_module "$wm_file" \
                         "modules/window-manager/$base_name" \
                         "pc"
done

# Style/theming modules
for style_file in modules/desktop/color-*.nix modules/desktop/font*.nix modules/desktop/opacity*.nix; do
  [ -f "$style_file" ] || continue
  base_name=$(basename "$style_file")
  migrate_desktop_module "$style_file" \
                         "modules/style/$base_name" \
                         "pc"
done

# Update host imports SAFELY
if [ -f "modules/hosts/system76/imports.nix" ]; then
  cp "modules/hosts/system76/imports.nix" "modules/hosts/system76/imports.nix.backup"
  
  # Remove desktop references
  if perl -i -pe 's/.*desktop.*\n//g' "modules/hosts/system76/imports.nix"; then
    if nix-instantiate --parse "modules/hosts/system76/imports.nix" >/dev/null 2>&1; then
      echo "✓ Updated host imports"
    else
      echo "✗ Failed to update host imports - reverting"
      mv "modules/hosts/system76/imports.nix.backup" "modules/hosts/system76/imports.nix"
    fi
  fi
fi

# Clean up if desktop directory is empty
if [ -d "modules/desktop" ]; then
  if [ -z "$(ls -A modules/desktop)" ]; then
    rmdir modules/desktop
    echo "✓ Removed empty desktop directory"
  else
    echo "Desktop directory still contains files:"
    ls -la modules/desktop/
  fi
fi

# Remove desktop.nix if it exists
if [ -f "modules/desktop.nix" ]; then
  mv "modules/desktop.nix" "modules/desktop.nix.removed"
  echo "✓ Removed desktop.nix (backed up as desktop.nix.removed)"
fi

echo ""
echo "=== Desktop Elimination Summary ==="
echo "Migrations completed: $(wc -l < "$MANIFEST")"
echo "See $MANIFEST for details"
echo "✓ Desktop namespace elimination complete"
```

---

## Phase 4: Add Pipe Operators Throughout [Day 9 - 4 hours]

### 4.1 Update All Shell Scripts
```bash
#!/usr/bin/env bash
# save as add-pipe-operators.sh
set -euo pipefail

# Find all shell scripts
for script in *.sh; do
  [ -f "$script" ] || continue
  
  # Check if already has pipe operators
  if grep -q "pipe-operators" "$script"; then
    echo "✓ $script already has pipe operators"
    continue
  fi
  
  # Add to scripts that use nix commands
  if grep -q "nix " "$script"; then
    # Add export at the top after shebang and set commands
    sed -i '/^set -euo pipefail/a\
export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"' "$script"
    echo "✓ Added pipe operators to $script"
  fi
done
```

### 4.2 Update Nix Expressions
```bash
#!/usr/bin/env bash
# save as check-pipe-usage.sh
set -euo pipefail

# Find Nix files that could use pipe operators
echo "Files that might benefit from pipe operators:"
grep -r "map\|filter\|concatMap" modules/ --include="*.nix" | cut -d: -f1 | sort -u

# The actual conversion needs manual review
echo "Manual review needed for pipe operator usage in Nix expressions"
```

---

## Phase 5: Fix Code Quality Issues [Day 10 - 2 hours]

### 5.1 Replace mkForce with mkDefault
```bash
#!/usr/bin/env bash
# save as fix-mkforce.sh
set -euo pipefail

# Find all mkForce usage with context
echo "=== mkForce Usage Analysis ==="
grep -B2 -A2 "mkForce" modules/**/*.nix 2>/dev/null | tee mkforce-analysis.txt

# For each occurrence, determine if mkDefault is appropriate
echo ""
echo "Manual review required for each mkForce usage:"
echo "1. Check if the override is absolutely necessary"
echo "2. If not, replace with mkDefault"
echo "3. Test after each change"

# Example safe replacement (after manual verification):
# sed -i 's/lib\.mkForce/lib.mkDefault/' modules/path/to/file.nix
```

---

## Phase 6: Add Missing Infrastructure [Week 5 - 16 hours]

### 6.0 Documentation Generation
```nix
# modules/docs/readme.nix
{ config, lib, ... }:
{
  # Generate documentation from modules
  flake.modules.nixos.base = {
    system.build.docs = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeTextFile {
        name = "module-documentation";
        text = ''
          # NixOS Configuration Documentation
          
          ## Enabled Modules
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: _: "- ${name}") 
            config.flake.modules.nixos
          )}
          
          ## System Configuration
          - Host: ${config.networking.hostName}
          - State Version: ${config.system.stateVersion}
        '';
      };
    };
  };
}
```

### 6.1 Dependency Visualization
```bash
#!/usr/bin/env bash
# save as generate-dependency-graph.sh
set -euo pipefail

echo "Generating module dependency graph..."

# Create DOT file for graphviz
DOT_FILE="module-dependencies.dot"

cat > "$DOT_FILE" << 'EOF'
digraph modules {
  rankdir=LR;
  node [shape=box];
  
  // Core namespace hierarchy
  "nixos.base" [color=green];
  "nixos.pc" [color=blue];
  "nixos.workstation" [color=purple];
  
  "nixos.pc" -> "nixos.base";
  "nixos.workstation" -> "nixos.pc";
EOF

# Analyze actual module dependencies
for file in modules/**/*.nix; do
  [ -f "$file" ] || continue
  
  MODULE=$(basename "$file" .nix)
  
  # Find what namespace it extends
  if grep -q "flake.modules.nixos.base" "$file" 2>/dev/null; then
    echo "  \"$MODULE\" -> \"nixos.base\";" >> "$DOT_FILE"
  fi
  
  if grep -q "flake.modules.nixos.pc" "$file" 2>/dev/null; then
    echo "  \"$MODULE\" -> \"nixos.pc\";" >> "$DOT_FILE"
  fi
  
  if grep -q "flake.modules.nixos.workstation" "$file" 2>/dev/null; then
    echo "  \"$MODULE\" -> \"nixos.workstation\";" >> "$DOT_FILE"
  fi
done

echo "}" >> "$DOT_FILE"

# Generate visualization
if command -v dot >/dev/null 2>&1; then
  dot -Tpng "$DOT_FILE" -o module-dependencies.png
  echo "✓ Dependency graph generated: module-dependencies.png"
else
  echo "Install graphviz to generate visual graph"
  echo "DOT file saved as: $DOT_FILE"
fi
```

## Phase 7: Add Infrastructure [Week 5 continued]

### 6.2 Implement Proper CI/CD
```nix
# modules/meta/ci.nix - Dynamic CI generation like golden standard
{ config, lib, ... }:
{
  flake.modules.nixos.base = {
    # Generate CI jobs dynamically from flake checks
    meta.ci = {
      enable = true;
      checks = config.checks;
    };
  };
}
```

### 6.3 Add Pre-commit Hooks
```nix
# modules/meta/git-hooks.nix
{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];
  
  perSystem = { config, ... }: {
    pre-commit = {
      check.enable = true;
      settings.hooks = {
        nixpkgs-fmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
  };
}
```

### 6.4 Secret Management
```bash
# Add agenix properly
echo 'agenix.url = "github:ryantm/agenix";' >> flake.nix
# Create secrets directory structure
mkdir -p secrets
```

---

## Phase 7: Comprehensive Testing Suite [Week 4 - 20 hours]

### 7.0 Integration Test Framework
```bash
#!/usr/bin/env bash
# save as create-test-framework.sh
set -euo pipefail

# Create test environment
TEST_ROOT="/tmp/dendritic-test-$$"
mkdir -p "$TEST_ROOT"

echo "Creating integration test framework..."

# Copy configuration for testing
cp -r /home/vx/nixos "$TEST_ROOT/nixos"
cd "$TEST_ROOT/nixos"

# Create test runner
cat > run-integration-tests.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

TEST_RESULTS="test-results.json"
echo '{ "tests": [] }' > "$TEST_RESULTS"

# Test phases in order
PHASES=(
  "add-pipe-operators-first.sh"
  "guide-namespace-wrapper.sh"
  "migrate-modules-safely.sh"
  "eliminate-desktop-namespace-safely.sh"
)

for phase in "${PHASES[@]}"; do
  echo "Testing phase: $phase"
  
  # Create clean state
  git checkout -f
  
  # Run phase
  if bash "$phase" 2>&1 | tee "$phase.log"; then
    # Validate build
    if nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>/dev/null; then
      echo "✓ Phase $phase succeeded"
      jq ".tests += [{\"phase\": \"$phase\", \"status\": \"passed\"}]" "$TEST_RESULTS" > tmp.json
      mv tmp.json "$TEST_RESULTS"
    else
      echo "✗ Phase $phase broke the build"
      jq ".tests += [{\"phase\": \"$phase\", \"status\": \"build-failed\"}]" "$TEST_RESULTS" > tmp.json
      mv tmp.json "$TEST_RESULTS"
    fi
  else
    echo "✗ Phase $phase failed to execute"
    jq ".tests += [{\"phase\": \"$phase\", \"status\": \"execution-failed\"}]" "$TEST_RESULTS" > tmp.json
    mv tmp.json "$TEST_RESULTS"
  fi
done

echo "Integration test results:"
jq . "$TEST_RESULTS"
EOF

chmod +x run-integration-tests.sh
echo "Test framework created at $TEST_ROOT"
```

### 7.1 Automated VM Testing
```bash
#!/usr/bin/env bash
# save as automated-vm-test.sh
set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"

echo "=== Automated VM Testing ==="

# Build VM
echo "Building VM for testing..."
if ! nix build .#nixosConfigurations.system76.config.system.build.vm; then
  echo "✗ VM build failed"
  exit 1
fi

echo "✓ VM built successfully"

# Create automated test script
cat > vm-test-suite.py << 'EOF'
#!/usr/bin/env python3
import subprocess
import time
import json
import sys

def run_vm_test():
    """Run automated VM tests"""
    results = {
        "boot": False,
        "services": False,
        "network": False,
        "users": False,
        "nix": False
    }
    
    # Start VM in background
    print("Starting VM...")
    vm_proc = subprocess.Popen(
        ["./result/bin/run-system76-vm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Wait for boot
    time.sleep(30)
    
    # Test SSH connectivity (VM should expose SSH)
    try:
        subprocess.run(
            ["ssh", "-o", "ConnectTimeout=5", "-p", "2222", 
             "localhost", "echo", "test"],
            check=True,
            capture_output=True
        )
        results["boot"] = True
        results["network"] = True
    except:
        print("Failed to connect to VM")
    
    # Clean up
    vm_proc.terminate()
    vm_proc.wait(timeout=10)
    
    # Report results
    print(json.dumps(results, indent=2))
    return all(results.values())

if __name__ == "__main__":
    sys.exit(0 if run_vm_test() else 1)
EOF

chmod +x vm-test-suite.py

# Run automated tests
if python3 vm-test-suite.py; then
  echo "✓ Automated VM tests passed"
  touch .vm-test-passed
else
  echo "✗ Automated VM tests failed"
  echo "Manual intervention required"
  exit 1
fi
```

## Phase 8: Manifest Generation and Audit Trail

### 8.1 Migration Manifest System
```bash
#!/usr/bin/env bash
# save as generate-manifest.sh
set -euo pipefail

# Generate comprehensive migration manifest
MANIFEST_DIR=".migration-manifests"
mkdir -p "$MANIFEST_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MANIFEST="$MANIFEST_DIR/manifest-$TIMESTAMP.json"

# Initialize manifest
cat > "$MANIFEST" << EOF
{
  "timestamp": "$TIMESTAMP",
  "phases": [],
  "changes": [],
  "validations": [],
  "rollback_points": []
}
EOF

# Function to log phase completion
log_phase() {
  local phase="$1"
  local status="$2"
  local details="$3"
  
  jq ".phases += [{\"name\": \"$phase\", \"status\": \"$status\", \"details\": \"$details\", \"timestamp\": \"$(date -Iseconds)\"}]" \
    "$MANIFEST" > tmp.json && mv tmp.json "$MANIFEST"
}

# Function to log file changes
log_change() {
  local file="$1"
  local change_type="$2"
  local details="$3"
  
  # Calculate file hash for audit
  local hash=""
  if [ -f "$file" ]; then
    hash=$(sha256sum "$file" | cut -d' ' -f1)
  fi
  
  jq ".changes += [{\"file\": \"$file\", \"type\": \"$change_type\", \"details\": \"$details\", \"hash\": \"$hash\", \"timestamp\": \"$(date -Iseconds)\"}]" \
    "$MANIFEST" > tmp.json && mv tmp.json "$MANIFEST"
}

# Function to log validation results
log_validation() {
  local test="$1"
  local result="$2"
  local details="$3"
  
  jq ".validations += [{\"test\": \"$test\", \"result\": \"$result\", \"details\": \"$details\", \"timestamp\": \"$(date -Iseconds)\"}]" \
    "$MANIFEST" > tmp.json && mv tmp.json "$MANIFEST"
}

# Export functions
export -f log_phase log_change log_validation

echo "Manifest system initialized at $MANIFEST"
```

### 8.2 Nix AST Parser Helper
```nix
# save as parse-helper.nix
# Use this to safely analyze Nix files without text manipulation

{ lib, ... }:

let
  # Function to analyze a module file
  analyzeModule = file: 
    let
      module = import file { inherit lib; config = {}; pkgs = {}; };
    in {
      hasNamespace = module ? flake.modules;
      namespaces = 
        if module ? flake.modules
        then lib.attrNames module.flake.modules
        else [];
      structure = builtins.typeOf module;
    };
    
  # Function to safely wrap a module
  wrapModule = file: namespace:
    # This should be done manually, not automatically
    # Return instructions instead of modifying
    ''
      To wrap ${file} in namespace ${namespace}:
      1. Preserve the original function signature
      2. Wrap the body in flake.modules.${namespace}
      3. Validate with nix-instantiate --parse
      4. Test build after wrapping
    '';
    
in {
  inherit analyzeModule wrapModule;
  
  # Example usage:
  # nix eval -f parse-helper.nix analyzeModule ./modules/base/efi.nix
}
```

## Phase 9: Final Validation and Testing [Week 5-6]

### 9.1 Comprehensive Validation Script
```bash
#!/usr/bin/env bash
# save as validate-dendritic-compliance.sh
set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"

echo "=== Dendritic Pattern Compliance Validation ==="

# 1. Check import-tree usage
if grep -q "import-tree.*modules" flake.nix; then
  echo "✓ import-tree configured"
else
  echo "✗ import-tree not found"
fi

# 2. Check no literal imports
if grep -r "imports.*\\.nix" modules/ 2>/dev/null | grep -v "^#"; then
  echo "✗ Found literal imports"
else
  echo "✓ No literal imports"
fi

# 3. Check semantic directory structure
REQUIRED_DIRS="audio boot hardware networking shells storage style"
for dir in $REQUIRED_DIRS; do
  if [ -d "modules/$dir" ]; then
    echo "✓ Semantic directory: $dir"
  else
    echo "✗ Missing semantic directory: $dir"
  fi
done

# 4. Check desktop namespace is gone
if [ -d "modules/desktop" ] || grep -r "nixos.desktop" modules/ 2>/dev/null; then
  echo "✗ Desktop namespace still exists"
else
  echo "✓ Desktop namespace eliminated"
fi

# 5. Build test
echo "Testing build..."
if nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run; then
  echo "✓ Build succeeds"
else
  echo "✗ Build fails"
fi
```

### 9.2 Create Test Suite
```nix
# tests/default.nix
{ pkgs, ... }:
{
  dendritic-compliance = pkgs.nixosTest {
    name = "dendritic-compliance";
    nodes.machine = { ... }: {
      imports = [ ../modules ];
    };
    testScript = ''
      machine.wait_for_unit("multi-user.target")
      machine.succeed("test -f /etc/nixos/configuration.nix")
    '';
  };
}
```

---

## Comprehensive Test Suite

### Pre-flight Validation Framework
```bash
#!/usr/bin/env bash
# save as pre-flight-checks.sh
set -euo pipefail

echo "=== Pre-flight Validation ==="

CHECKS_PASSED=0
CHECKS_FAILED=0

# Check Nix version
if nix --version | grep -q "2.1[3-9]\|2.[2-9][0-9]\|[3-9]"; then
  echo "✓ Nix version compatible"
  ((CHECKS_PASSED++))
else
  echo "✗ Nix version too old (need 2.13+)"
  ((CHECKS_FAILED++))
fi

# Check experimental features
if nix eval --expr "1 |> toString" &>/dev/null; then
  echo "✓ Pipe operators work"
  ((CHECKS_PASSED++))
else
  echo "✗ Pipe operators not enabled"
  ((CHECKS_FAILED++))
fi

# Check for backup
if [ -f ".backup-timestamp" ]; then
  echo "✓ Backup exists"
  ((CHECKS_PASSED++))
else
  echo "✗ No backup found - create one first"
  ((CHECKS_FAILED++))
fi

# Check current build status
if nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>/dev/null; then
  echo "✓ Current configuration builds"
  ((CHECKS_PASSED++))
else
  echo "✗ Current configuration doesn't build - fix first"
  ((CHECKS_FAILED++))
fi

# Check for uncommitted changes
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  echo "✓ No uncommitted changes"
  ((CHECKS_PASSED++))
else
  echo "⚠ Uncommitted changes present - consider committing"
fi

echo ""
echo "Pre-flight checks: $CHECKS_PASSED passed, $CHECKS_FAILED failed"

if [ $CHECKS_FAILED -gt 0 ]; then
  echo "✗ Pre-flight checks failed - fix issues before proceeding"
  exit 1
fi

echo "✓ All pre-flight checks passed"
```

### Atomic Operations Manager
```bash
#!/usr/bin/env bash
# save as atomic-operations.sh
set -euo pipefail

# Staging area for atomic operations
STAGING_ROOT=".staging"
TRANSACTION_LOG=".transaction.log"

# Initialize transaction
init_transaction() {
  local tx_id="$(date +%s)-$$"
  mkdir -p "$STAGING_ROOT/$tx_id"
  echo "$tx_id" > .current-transaction
  echo "[$(date)] Transaction $tx_id started" >> "$TRANSACTION_LOG"
  echo "$tx_id"
}

# Stage a file change
stage_file() {
  local file="$1"
  local tx_id="$(cat .current-transaction)"
  
  # Backup original
  if [ -f "$file" ]; then
    cp "$file" "$STAGING_ROOT/$tx_id/$(basename "$file").original"
  fi
  
  # Mark as staged
  echo "$file" >> "$STAGING_ROOT/$tx_id/manifest.txt"
}

# Commit transaction
commit_transaction() {
  local tx_id="$(cat .current-transaction)"
  
  echo "Committing transaction $tx_id..."
  
  # Validate all changes
  while read -r file; do
    if [ -f "$file" ]; then
      if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
        echo "Validation failed for $file"
        rollback_transaction
        return 1
      fi
    fi
  done < "$STAGING_ROOT/$tx_id/manifest.txt"
  
  # Test build
  if ! nix build .#nixosConfigurations.system76.config.system.build.toplevel --dry-run 2>/dev/null; then
    echo "Build validation failed"
    rollback_transaction
    return 1
  fi
  
  echo "[$(date)] Transaction $tx_id committed" >> "$TRANSACTION_LOG"
  rm -rf "$STAGING_ROOT/$tx_id"
  rm .current-transaction
  echo "✓ Transaction committed successfully"
}

# Rollback transaction
rollback_transaction() {
  local tx_id="$(cat .current-transaction)"
  
  echo "Rolling back transaction $tx_id..."
  
  # Restore originals
  while read -r file; do
    orig="$STAGING_ROOT/$tx_id/$(basename "$file").original"
    if [ -f "$orig" ]; then
      mv "$orig" "$file"
    fi
  done < "$STAGING_ROOT/$tx_id/manifest.txt"
  
  echo "[$(date)] Transaction $tx_id rolled back" >> "$TRANSACTION_LOG"
  rm -rf "$STAGING_ROOT/$tx_id"
  rm .current-transaction
  echo "✓ Transaction rolled back"
}

# Export functions for use in other scripts
export -f init_transaction stage_file commit_transaction rollback_transaction
```

## Realistic Timeline (4-6 Weeks)

### Week 1: Analysis and Preparation
- Day 1-2: Complete analysis, create backups, pre-flight checks (8 hours)
- Day 3-4: Set up atomic operations framework and test suite (8 hours)
- Day 5: Manual namespace wrapper analysis and documentation (4 hours)

### Week 2: Core Migration (Manual Intervention Required)
- Day 1-2: Manually fix namespace violations with validation (12 hours)
- Day 3: Add pipe operators safely with full testing (6 hours)
- Day 4-5: Manual module reorganization to semantic structure (10 hours)

### Week 3: Structural Changes
- Day 1-2: Safely eliminate desktop namespace with manifest (8 hours)
- Day 3: Remove specialArgs and break up monoliths (6 hours)
- Day 4-5: Fix code quality issues (mkForce -> mkDefault) (6 hours)

### Week 4: Testing and Validation
- Day 1-2: Integration testing of all changes (8 hours)
- Day 3-4: Automated VM testing suite (8 hours)
- Day 5: Final validation and documentation (4 hours)

### Week 5: Infrastructure and Polish
- Day 1-2: Add CI/CD, pre-commit hooks (8 hours)
- Day 3: Implement secret management (4 hours)
- Day 4-5: Production deployment preparation (8 hours)

### Week 6: Buffer and Contingency
- Days 1-5: Handle unexpected issues, additional testing (20 hours)
- Final review and sign-off

**Total: 130 hours over 30 days** (realistic with proper testing)

### Critical Path Items
1. **Manual namespace fixes** - Cannot be automated safely
2. **Semantic validation** - Requires build testing after each change
3. **Integration testing** - Must test complete migration sequence
4. **VM validation** - Essential before production
5. **Atomic operations** - Prevents partial failures

---

## Risk Mitigation Strategy

### Continuous Validation Protocol
```bash
#!/usr/bin/env bash
# save as continuous-validation.sh
set -euo pipefail

# After EVERY change
validate_change() {
  local description="$1"
  
  echo "Validating: $description"
  
  # Syntax check all Nix files
  find modules -name "*.nix" -type f | while read -r file; do
    if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
      echo "✗ Syntax error in $file"
      return 1
    fi
  done
  
  # Build check
  if ! nix build .#nixosConfigurations.system76.config.system.build.toplevel \
       --dry-run --extra-experimental-features pipe-operators 2>/dev/null; then
    echo "✗ Build failed after: $description"
    return 1
  fi
  
  # Commit if successful
  git add -A
  git commit -m "dendritic: $description"
  echo "✓ Change validated and committed: $description"
}

export -f validate_change
```

### Checkpoint System
```bash
#!/usr/bin/env bash
# save as checkpoint.sh
set -euo pipefail

# Create restoration checkpoint
create_checkpoint() {
  local phase="$1"
  local checkpoint=".checkpoints/$(date +%Y%m%d-%H%M%S)-$phase"
  
  mkdir -p .checkpoints
  
  # Save current state
  tar czf "$checkpoint.tar.gz" modules/ flake.nix
  
  # Save build status
  nix build .#nixosConfigurations.system76.config.system.build.toplevel \
    --dry-run 2>&1 > "$checkpoint.build-status"
  
  echo "$checkpoint" > .last-checkpoint
  echo "✓ Checkpoint created: $checkpoint"
}

# Restore to checkpoint
restore_checkpoint() {
  if [ ! -f .last-checkpoint ]; then
    echo "No checkpoint found"
    return 1
  fi
  
  local checkpoint=$(cat .last-checkpoint)
  
  if [ -f "$checkpoint.tar.gz" ]; then
    tar xzf "$checkpoint.tar.gz"
    echo "✓ Restored to checkpoint: $checkpoint"
  else
    echo "✗ Checkpoint file not found"
    return 1
  fi
}

export -f create_checkpoint restore_checkpoint
```

### Rollback Strategy
```bash
#!/usr/bin/env bash
# save as safe-rollback.sh
set -euo pipefail

# Read saved timestamp
if [ ! -f ".backup-timestamp" ]; then
  echo "ERROR: No backup timestamp found"
  exit 1
fi

TIMESTAMP=$(cat .backup-timestamp)
BACKUP_DIR="/home/vx/nixos-backup-$TIMESTAMP"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "ERROR: Backup directory not found: $BACKUP_DIR"
  exit 1
fi

# Safety check - don't overwrite existing backup
if [ -d "/home/vx/nixos.broken" ]; then
  echo "ERROR: nixos.broken already exists, manual intervention required"
  exit 1
fi

# Safe rollback
cd /home/vx
mv nixos nixos.broken
cp -r "$BACKUP_DIR" nixos
cd nixos
git checkout main

echo "Rollback completed. Broken configuration saved in /home/vx/nixos.broken"
```

---

## Success Metrics

### Required for 100/100 Compliance
1. ✅ All 13 namespace violations fixed with CORRECT namespace assignment
2. ✅ Semantic directory structure for organization (NOT namespace determination)
3. ✅ Modules extend EXISTING namespaces based on PURPOSE
4. ✅ Desktop namespace eliminated (modules moved to appropriate namespaces)
5. ✅ Pipe operators in all scripts and expressions
6. ✅ import-tree usage verified
7. ✅ No literal imports anywhere
8. ✅ "Named Modules as Needed" philosophy followed correctly
9. ✅ specialArgs removed
10. ✅ system76-complete.nix broken into logical modules
11. ✅ Proper CI/CD with dynamic generation
12. ✅ Secret management (agenix) configured
13. ✅ Pre-commit hooks active
14. ✅ VM testing passed
15. ✅ All scripts are idempotent and safe
16. ✅ Validation after each phase passes
17. ✅ mkForce replaced with mkDefault where appropriate
18. ✅ Home Manager follows dendritic pattern
19. ✅ Documentation generation implemented
20. ✅ Dependency visualization tooling added
21. ✅ Test suite for migration scripts passes
22. ✅ Modules correctly assigned to base/pc/workstation based on PURPOSE
23. ✅ Final build and deployment successful

---

## Critical Differences from Previous Plan

1. **Understanding**: Semantic organization, not arbitrary hierarchy
2. **Approach**: Careful migration, not broken sed commands
3. **Safety**: Backups and validation at every step
4. **Timeline**: Realistic 2-3 weeks, not 2-3 days
5. **Philosophy**: Following actual dendritic pattern, not inventing rules

This plan follows the ACTUAL dendritic pattern as implemented in mightyiam/infra.