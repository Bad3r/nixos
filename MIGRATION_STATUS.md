# Migration Status: Dendritic Pattern Adoption from mightyiam/infra

## Executive Summary

Migrating from traditional NixOS configuration to the exact dendritic pattern used in mightyiam/infra. This migration will reuse 37+ modules directly from infra and create 12 custom modules for System76-specific needs.

## 🎯 Migration Phases

### Phase 1: Foundation [0/7] 🔴
- [ ] Copy infra's flake.nix structure with import-tree
- [ ] Create system76/ host directory structure
- [ ] Copy and adapt owner.nix with vx user details
- [ ] Copy ssh.nix and add actual SSH keys
- [ ] Copy sudo.nix from infra
- [ ] Copy pc.nix and workstation.nix from infra
- [ ] Test basic flake evaluation

### Phase 2: Core System [0/7] 🔴
- [ ] Copy boot/efi.nix from infra
- [ ] Copy boot/storage.nix from infra
- [ ] Copy storage/swap.nix from infra
- [ ] Copy nvidia-gpu.nix base module
- [ ] Create system76-specific nvidia config
- [ ] Copy audio/pipewire.nix from infra
- [ ] Copy bluetooth.nix from infra

### Phase 3: Desktop Environment [0/4] 🔴
- [ ] Create kde-plasma.nix (custom - infra uses Sway)
- [ ] Create plasma-packages.nix for KDE apps
- [ ] Copy style/ modules from infra (Stylix)
- [ ] Configure display manager (SDDM)

### Phase 4: Applications [0/6] 🔴
- [ ] Copy all web-browsers/ modules from infra
- [ ] Copy all terminal/ modules from infra
- [ ] Create terminal/kitty.nix (custom)
- [ ] Create development.nix with dev tools
- [ ] Copy file-management/ modules from infra
- [ ] Create packages/ directory for custom apps

### Phase 5: Development Environment [0/5] 🔴
- [ ] Copy all git/ modules from infra
- [ ] Copy all shells/ modules from infra
- [ ] Copy all nix/ modules from infra
- [ ] Copy virtualization/docker.nix from infra
- [ ] Create language-specific tool modules

### Phase 6: Home Manager [0/4] 🔴
- [ ] Copy home-manager/nixos.nix from infra
- [ ] Copy home-manager/base.nix from infra
- [ ] Create home-vx.nix for user config
- [ ] Configure user-specific programs

### Phase 7: Custom Packages [0/3] 🔴
- [ ] Create packages/logseq.nix
- [ ] Create packages/cursor.nix
- [ ] Create system76-support.nix

## 📊 Module Migration Matrix

| Category | From infra | Custom | Total | Status |
|----------|------------|--------|-------|--------|
| Core System | 6 | 0 | 6 | ❌ |
| Host Config | 0 | 6 | 6 | ❌ |
| Boot | 3 | 0 | 3 | ❌ |
| Storage | 4 | 0 | 4 | ❌ |
| Networking | 5 | 0 | 5 | ❌ |
| Audio | 4 | 0 | 4 | ❌ |
| Desktop | 0 | 2 | 2 | ❌ |
| Browsers | 4 | 0 | 4 | ❌ |
| Terminal | 3 | 1 | 4 | ❌ |
| Shells | 14 | 0 | 14 | ❌ |
| Git | 6 | 0 | 6 | ❌ |
| File Mgmt | 7 | 0 | 7 | ❌ |
| Nix Config | 5 | 0 | 5 | ❌ |
| Style | 6 | 0 | 6 | ❌ |
| Packages | 0 | 3 | 3 | ❌ |
| **TOTAL** | **67** | **12** | **79** | **0%** |

## 🚨 Critical Path Items

### Immediate Blockers
1. **SSH Keys**: Need actual SSH public key for modules/ssh.nix
2. **Hardware UUIDs**: Need actual disk UUIDs for system76/hardware.nix
3. **Host ID**: Generate with `head -c 8 /etc/machine-id`
4. **NVIDIA Bus IDs**: Verify with `lspci | grep VGA`

### Required Information
```bash
# Get host ID
head -c 8 /etc/machine-id

# Get disk UUIDs
lsblk -f | grep -E "ext4|vfat|swap"

# Get NVIDIA bus IDs
nix-shell -p pciutils --run "lspci | grep VGA"

# Generate SSH key if needed
ssh-keygen -t ed25519 -C "bad3r@unsigned.sh"
cat ~/.ssh/id_ed25519.pub
```

## 📁 Directory Structure Progress

```
modules/
├── system76/              ❌ Not created
│   ├── imports.nix        ❌
│   ├── hostname.nix       ❌
│   ├── host-id.nix        ❌
│   ├── state-version.nix  ❌
│   ├── nvidia-gpu.nix     ❌
│   └── hardware.nix       ❌
├── configurations/        ❌ Not copied
│   └── nixos.nix         ❌
├── owner.nix             ❌ Not adapted
├── ssh.nix               ❌ Not copied
├── sudo.nix              ❌ Not copied
├── pc.nix                ❌ Not copied
├── workstation.nix       ❌ Not copied
└── [37+ infra modules]   ❌ Not copied
```

## 🔄 Module Reuse Plan

### Direct Copy from infra (No Modifications)
- `sudo.nix` - sudo-rs configuration
- `pc.nix` - base PC module
- `workstation.nix` - workstation extensions
- `configurations/nixos.nix` - configuration framework
- `bluetooth.nix` - Bluetooth support
- All `boot/` modules (3 files)
- All `storage/` modules (4 files)
- All `shells/` modules (14 files)
- All `git/` modules (6 files)
- All `file-management/` modules (7 files)
- All `nix/` modules (5 files)
- All `style/` modules (6 files)
- All `web-browsers/` modules (4 files)
- `audio/pipewire.nix` - PipeWire audio
- `virtualization/docker.nix` - Docker support

### Copy & Modify from infra
- `owner.nix` → Update with vx user details
- `ssh.nix` → Add actual SSH keys
- `nvidia-gpu.nix` → Use base, create host-specific

### Custom Modules (Not in infra)
- `system76/` directory (6 files) - Host configuration
- `kde-plasma.nix` - KDE Plasma 6 (infra uses Sway)
- `plasma-packages.nix` - KDE applications
- `system76-support.nix` - System76 hardware support
- `terminal/kitty.nix` - Kitty terminal
- `development.nix` - Development tools
- `packages/logseq.nix` - Logseq custom build
- `packages/cursor.nix` - Cursor editor
- `home-vx.nix` - User-specific home config

## ⚡ Quick Start Commands

### 1. Start Migration
```bash
# Create base structure
cd /home/vx/nixos
mkdir -p modules/system76

# Copy infra's configurations module
cp /home/vx/git/infra/modules/configurations/nixos.nix modules/configurations/

# Copy core modules
cp /home/vx/git/infra/modules/{owner,ssh,sudo,pc,workstation}.nix modules/

# Update owner.nix with your details
$EDITOR modules/owner.nix
```

### 2. Bulk Copy infra Modules
```bash
# Copy entire directories
cp -r /home/vx/git/infra/modules/{boot,storage,shells,git,file-management,nix,style,web-browsers,audio} modules/

# Copy individual modules
cp /home/vx/git/infra/modules/{bluetooth,nvidia-gpu}.nix modules/

# Copy virtualization
cp -r /home/vx/git/infra/modules/virtualization modules/

# Copy terminal configs
cp -r /home/vx/git/infra/modules/terminal modules/
```

### 3. Test Build
```bash
# Check flake validity
nix flake check

# Build without switching
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Build VM for testing
nixos-rebuild build-vm --flake .#system76
```

## 📈 Progress Metrics

- **Total Modules**: 79
- **Completed**: 0
- **In Progress**: 0
- **Blocked**: 4 (waiting for hardware info)
- **Completion**: 0%

### Daily Goals
- Day 1-2: Complete Phase 1 (Foundation)
- Day 3-4: Complete Phase 2 (Core System)
- Day 5-6: Complete Phase 3-4 (Desktop & Apps)
- Day 7-8: Complete Phase 5-6 (Dev & Home)
- Day 9-10: Complete Phase 7 & Testing

## 🛠️ Validation Tests

### Level 1: Flake Evaluation
```bash
nix flake check
nix eval .#nixosConfigurations.system76.config.system.stateVersion
```

### Level 2: Build Test
```bash
nix build .#nixosConfigurations.system76.config.system.build.toplevel
```

### Level 3: VM Test
```bash
nixos-rebuild build-vm --flake .#system76
./result/bin/run-system76-vm
```

### Level 4: Deployment
```bash
sudo nixos-rebuild switch --flake .#system76
```

## 📝 Notes

### Pattern Compliance
- ✅ Using `configurations.nixos.system76.module` pattern
- ✅ Host files in dedicated directory
- ✅ Metadata in `flake.meta.owner`
- ✅ No explicit imports (automatic via import-tree)
- ✅ Modules export to `flake.modules.nixos.*`
- ✅ Functions for modules needing `pkgs`
- ✅ Pipe operators for transformations

### Key Differences from old_nixos
1. **Structure**: Flat modules/ vs hierarchical common/linux/darwin
2. **Imports**: Automatic vs explicit paths
3. **Host Config**: Directory with multiple files vs single file
4. **Namespaces**: flake.modules.nixos.* vs direct nixosConfigurations
5. **Composition**: base → pc → workstation hierarchy

### Risk Mitigation
- Keep old_nixos as backup
- Test each phase in VM before deployment
- Document all custom modifications
- Use version control for rollback

## 🚀 Next Actions

1. **Get Hardware Info** (Priority: CRITICAL)
   ```bash
   ./get-hardware-info.sh > hardware-info.txt
   ```

2. **Start Copying Modules** (Priority: HIGH)
   ```bash
   ./copy-infra-modules.sh
   ```

3. **Create Host Configuration** (Priority: HIGH)
   ```bash
   ./create-system76-host.sh
   ```

4. **Test Basic Build** (Priority: MEDIUM)
   ```bash
   nix flake check
   ```

---

*Last Updated: $(date)*
*Migration Pattern: mightyiam/infra dendritic*
*Target System: System76 with NVIDIA GPU*