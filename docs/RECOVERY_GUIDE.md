# NixOS System Recovery Guide using EndeavourOS Live USB

## Part 1: Disable NVIDIA GPU at Boot (Emergency Boot)

### For systemd-boot (Your Current Bootloader)

1. **At boot, access systemd-boot menu** by pressing `Space` or any key
2. **Select your boot entry** and press `e` to edit
3. **Add to kernel parameters:**
   ```
   modprobe.blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0
   ```
4. **Press Enter** to boot with disabled NVIDIA

### For GRUB2 (Alternative Systems)

1. **At GRUB menu**, highlight your boot entry and press `e`
2. **Find the line starting with** `linux` or `linux16`
3. **Add to the end of that line:**
   ```
   modprobe.blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0 nomodeset
   ```
4. **Press Ctrl+X or F10** to boot

## Part 2: NixOS Recovery via EndeavourOS Live USB

### Prerequisites
- EndeavourOS Live USB (already prepared)
- Internet connection
- Your GitHub repo with fixed NixOS configuration

### Step 1: Boot EndeavourOS & Initial Setup

```bash
# 1.1 - Connect to internet
# For WiFi:
nmtui
# OR
iwctl

# 1.2 - Verify internet connection
ping -c 3 github.com

# 1.3 - Update package database (optional but recommended)
sudo pacman -Sy

# 1.4 - Install useful tools
sudo pacman -S git vim tmux htop
```

### Step 2: Install Nix Package Manager

```bash
# 2.1 - Download and install Nix (single-user mode for simplicity)
curl -L https://nixos.org/nix/install | sh

# 2.2 - Activate Nix environment
source ~/.nix-profile/etc/profile.d/nix.sh

# 2.3 - Verify Nix installation
nix --version

# 2.4 - Configure Nix experimental features
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### Step 3: Install NixOS Recovery Tools

```bash
# 3.1 - Install NixOS tools package
nix-env -iA nixpkgs.nixos-install-tools

# 3.2 - Verify tools are available
which nixos-enter
which nixos-install
which nixos-rebuild

# 3.3 - Alternative: Use nix-shell for temporary access
# nix-shell -p nixos-install-tools
```

### Step 4: Decrypt and Mount NixOS System

```bash
# 4.1 - Identify your drives (verify UUIDs match)
lsblk -f
ls -la /dev/disk/by-uuid/

# 4.2 - Decrypt LUKS volumes
# Root partition
sudo cryptsetup luksOpen /dev/disk/by-uuid/de5ef033-553b-4943-be41-09125eb815b2 cryptroot

# Swap partition (optional, but recommended)
sudo cryptsetup luksOpen /dev/disk/by-uuid/555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec cryptswap

# 4.3 - Verify decrypted devices exist
ls -la /dev/mapper/

# 4.4 - Mount root filesystem
sudo mount /dev/mapper/cryptroot /mnt

# 4.5 - Mount boot partition
sudo mount /dev/disk/by-uuid/98A9-C26F /mnt/boot

# 4.6 - Verify mounts
df -h | grep /mnt

# 4.7 - Activate swap (optional)
sudo swapon /dev/mapper/cryptswap
swapon --show
```

### Step 5: Prepare Fixed Configuration

```bash
# 5.1 - Clone your fixed NixOS configuration
cd /tmp
git clone https://github.com/Bad3r/nixos-dendritic.git

# 5.2 - Verify the fix is present
grep -n "i915" /tmp/nixos-dendritic/modules/system76/boot.nix
# Should show: initrd.kernelModules = [ "i915" ];

# 5.3 - Verify NVIDIA modules are removed from initrd
grep -n "nvidia" /tmp/nixos-dendritic/modules/system76/boot.nix
# Should NOT show nvidia modules in initrd.kernelModules
```

### Step 6: Rebuild NixOS System

#### Option A: Using nixos-enter (Recommended)

```bash
# 6A.1 - Enter NixOS chroot environment
sudo nixos-enter --root /mnt

# 6A.2 - Inside chroot: Navigate to config directory
cd /home/odd/git/nixos-dendritic

# 6A.3 - Pull latest changes
git pull origin main

# 6A.4 - Rebuild boot configuration
nixos-rebuild boot --flake .#system76 \
  --extra-experimental-features "nix-command flakes pipe-operators"

# 6A.5 - Exit chroot
exit
```

#### Option B: Using nixos-install (Direct rebuild)

```bash
# 6B.1 - Rebuild directly from cloned repo
sudo nixos-install \
  --flake /tmp/nixos-dendritic#system76 \
  --root /mnt \
  --no-root-password \
  --option experimental-features "nix-command flakes pipe-operators"
```

### Step 7: Cleanup and Reboot

```bash
# 7.1 - Sync filesystem buffers
sync

# 7.2 - Unmount filesystems
sudo swapoff /dev/mapper/cryptswap
sudo umount /mnt/boot
sudo umount /mnt

# 7.3 - Close LUKS devices
sudo cryptsetup luksClose cryptswap
sudo cryptsetup luksClose cryptroot

# 7.4 - Reboot
sudo reboot
```

## Post-Recovery Verification

After successful boot:

```bash
# Verify NVIDIA modules are NOT in initrd
sudo lsinitrd | grep -i nvidia
# Should show no results or only firmware files

# Check current boot configuration
nixos-rebuild list-generations

# Verify Intel graphics module is loaded
lsmod | grep i915

# Check NVIDIA modules loaded (should be in main system only)
lsmod | grep nvidia
```

## Troubleshooting

### If nixos-rebuild fails with "command not found"

```bash
# Ensure Nix environment is loaded
source /etc/profile
source ~/.nix-profile/etc/profile.d/nix.sh
export PATH=/run/current-system/sw/bin:$PATH
```

### If boot still fails after rebuild

1. Boot EndeavourOS again
2. Mount and chroot as before
3. Check the initrd contents:
   ```bash
   sudo nixos-enter --root /mnt
   nix-store -qR /run/current-system | grep initrd
   lsinitcpio -a /boot/initramfs-*.img | grep -i nvidia
   ```

### If LUKS decrypt fails

```bash
# Verify UUID is correct
sudo blkid | grep crypto_LUKS

# Test decrypt manually
sudo cryptsetup -v luksOpen /dev/[your-device] test
```

## Important Notes

1. **Do NOT skip Step 5.2** - Verify the fix is actually in your config
2. **Use Option A (nixos-enter)** if you need to debug or run multiple commands
3. **Use Option B (nixos-install)** for a quick, automated rebuild
4. **The swap LUKS** is optional but recommended to mount for system rebuilds
5. **Keep the EndeavourOS USB** until you've successfully booted at least once

## Success Indicators

✅ `nixos-rebuild` completes without errors  
✅ New generation created (check with `nixos-rebuild list-generations`)  
✅ System boots without kernel panic  
✅ Desktop environment loads properly  
✅ NVIDIA drivers work (after boot, not in initrd)