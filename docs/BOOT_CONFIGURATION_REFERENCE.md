# Boot Configuration Reference

## System Disk Layout

```
nvme0n1
├─nvme0n1p1 (Boot)
│ UUID: 98A9-C26F
│ Type: vfat (FAT32)
│ Mount: /boot
│
├─nvme0n1p2 (Root - Encrypted)
│ UUID: de5ef033-553b-4943-be41-09125eb815b2
│ Type: LUKS encrypted volume
│ └─Decrypted as: luks-de5ef033-553b-4943-be41-09125eb815b2
│   UUID: 54df1eda-4dc3-40d0-a6da-8d1d7ee612b2
│   Type: ext4
│   Mount: /
│
└─nvme0n1p3 (Swap - Encrypted)
  UUID: 555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec
  Type: LUKS encrypted volume
  └─Decrypted as: luks-555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec
    UUID: 72b0d736-e0c5-4f72-bc55-f50f7492ceef
    Type: swap
    Mount: [SWAP]
```

## Configuration Components

### Boot Loader & Filesystems

**Location**: `/home/vx/nixos/modules/system76/hardware-config.nix`

```nix
boot.loader = {
  systemd-boot = {
    enable = true;            # systemd-boot UEFI boot loader
    editor = false;           # Disabled for security
    consoleMode = "auto";     # Automatic console resolution
    configurationLimit = 3;   # Keep only 3 generations
  };
  efi.canTouchEfiVariables = true;  # Allow EFI variable modification
};

fileSystems = {
  "/" = {
    device = "/dev/disk/by-uuid/54df1eda-4dc3-40d0-a6da-8d1d7ee612b2";
    fsType = "ext4";
  };
  "/boot" = {
    device = "/dev/disk/by-uuid/98A9-C26F";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };
};
```

### LUKS Encryption

**Location**: `/home/vx/nixos/modules/system76/luks.nix`

- Root LUKS UUID: `de5ef033-553b-4943-be41-09125eb815b2`
- Swap LUKS UUID: `555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec`

Both volumes require password entry during boot.

### Swap Configuration

**Location**: `/home/vx/nixos/modules/system76/swap.nix`

- Size: 34.2G (sufficient for 32GB RAM system)
- Encrypted via LUKS
- References decrypted swap device

### Boot Optimization

**Location**: `/home/vx/nixos/modules/boot/compression.nix`

- Compression: `zstd` (optimal balance of speed and compression)

### NVIDIA Early Boot Support

**Location**: `/home/vx/nixos/modules/system76/boot.nix`

- NVIDIA kernel modules loaded in initrd
- Nouveau driver blacklisted
- Power management parameters configured

## Migration History

### Critical Issue Resolution

When migrating to the Dendritic Pattern, an attempt was made to separate boot configuration into a dedicated `hardware/efi.nix` module. This failed with an undefined variable error because the import system couldn't properly recognize the named module.

**Solution**: Boot configuration was consolidated in `system76/hardware-config.nix` where it functions correctly. This approach is acceptable because:

1. Boot configuration is critical - failures prevent system boot
2. The Dendritic Pattern allows host-specific configuration
3. The configuration is properly recognized and applied
4. All critical boot/filesystem config is maintainable in one location

### Applied Fixes

1. **LUKS UUID Correction**: Updated from old UUID to actual `de5ef033-553b-4943-be41-09125eb815b2`
2. **Boot Configuration Consolidation**: Moved to hardware-config.nix for reliability
3. **Filesystem Configuration**: Both root and boot filesystems properly defined
4. **LUKS Device Configuration**: Root and swap encryption properly handled

## Verification Commands

```bash
# Verify boot loader is enabled
nix eval .#nixosConfigurations.system76.config.boot.loader.systemd-boot.enable
# Expected: true

# Check configuration limit
nix eval .#nixosConfigurations.system76.config.boot.loader.systemd-boot.configurationLimit
# Expected: 3

# Verify EFI variables access
nix eval .#nixosConfigurations.system76.config.boot.loader.efi.canTouchEfiVariables
# Expected: true

# Check compression method
nix eval .#nixosConfigurations.system76.config.boot.initrd.compressor
# Expected: "zstd"

# Verify disk UUIDs match system
lsblk -f
```

## Build and Switch Commands

```bash
# Build the configuration
nix build .#nixosConfigurations.system76.config.system.build.toplevel \
  --extra-experimental-features "nix-command flakes pipe-operators"

# Switch to the new configuration
sudo nixos-rebuild switch --flake .#system76 \
  --extra-experimental-features "nix-command flakes pipe-operators"
```

## Important Notes

1. **LUKS Password**: Two password prompts during boot (root and swap)
2. **Generation Limit**: Only 3 previous configurations kept to save space
3. **Boot Editor**: Disabled for security (`editor = false`)
4. **Compression**: zstd provides faster boot with better compression ratio
5. **UUID Documentation**: The UUIDs listed are specific to the current hardware:
   - Root: `54df1eda-4dc3-40d0-a6da-8d1d7ee612b2`
   - Boot: `98A9-C26F`
   - Root LUKS: `de5ef033-553b-4943-be41-09125eb815b2`
   - Swap LUKS: `555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec`

## Verification Checklist

- [x] Boot partition UUID matches: `98A9-C26F`
- [x] Root partition UUID matches: `54df1eda-4dc3-40d0-a6da-8d1d7ee612b2`
- [x] Root LUKS UUID correct: `de5ef033-553b-4943-be41-09125eb815b2`
- [x] Swap LUKS UUID verified: `555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec`
- [x] systemd-boot enabled
- [x] EFI variables accessible
- [x] Filesystems properly mounted
- [x] NVIDIA early boot configured
- [x] Compression optimized

## Status

✅ **BOOT CONFIGURATION COMPLETE AND VERIFIED**

The system is properly configured to boot with:

- Full disk encryption (LUKS)
- systemd-boot UEFI boot loader
- Optimized compression
- NVIDIA GPU support
- All filesystems correctly mounted

Configuration has been thoroughly verified against actual hardware with all UUIDs confirmed to match.
