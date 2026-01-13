# System76 Oryx Pro NixOS Configuration

## Module Structure

All System76-specific configuration lives in `modules/system76/`:

| File                  | Purpose                                  |
| --------------------- | ---------------------------------------- |
| `hardware-config.nix` | Filesystems, LUKS, firmware, bluetooth   |
| `nvidia-gpu.nix`      | NVIDIA PRIME sync/offload                |
| `boot.nix`            | Kernel, crash dump, NVIDIA params        |
| `services.nix`        | power management, scheduler, logging     |
| `support.nix`         | System76 kernel modules, firmware daemon |
| `packages.nix`        | System76 utilities, unfree allowlist     |

## Hardware Support

```nix
# modules/system76/support.nix
hardware.system76 = {
  kernel-modules.enable = true;   # Fan monitoring, EC communication
  firmware-daemon.enable = true;  # Firmware updates via fwupd
  power-daemon.enable = true;     # Thermal management, power profiles, battery thresholds
};

boot.kernelParams = [ "system76_acpi.brightness_hwmon=1" ];
services.fwupd.enable = true;
```

## Hardware Firmware

Selective approach - only needed firmware declared explicitly:

```nix
# modules/system76/hardware-config.nix
hardware = {
  cpu.intel.updateMicrocode = true;

  firmware = lib.mkAfter [
    pkgs.linux-firmware  # Intel 8265 WiFi/BT, i915 GPU
    pkgs.sof-firmware    # Intel audio DSP
    pkgs.wireless-regdb  # WiFi regulatory
  ];
};

# modules/base/hardware-scan.nix
hardware = {
  enableRedistributableFirmware = false;
  enableAllFirmware = false;
};
```

All firmware is redistributable (no unfree). See [system76-hardware.md](system76-hardware.md) for firmware details.

## Services

```nix
# modules/system76/services.nix
services = {
  # Thermal management via system76-power (hardware.system76.power-daemon)
  thermald.enable = false;

  system76-scheduler.enable = true;  # Desktop responsiveness
  power-profiles-daemon.enable = false;  # Conflicts with system76-power
};

powerManagement.cpuFreqGovernor = "performance";
programs.coolercontrol.enable = false;  # Conflicts with EC
```

### Power Profiles & Battery Thresholds

```bash
# Power profiles
system76-power profile performance  # Maximum performance
system76-power profile balanced     # Balanced (default)
system76-power profile battery      # Battery saving

# Battery charge thresholds (requires EC support)
system76-power charge-thresholds    # View current thresholds
sudo system76-power charge-thresholds --profile max_lifespan  # 40-80%
sudo system76-power charge-thresholds --profile balanced      # 50-90%
sudo system76-power charge-thresholds --profile full_charge   # 96-100%
```

## NVIDIA GPU

```nix
# modules/system76/nvidia-gpu.nix
options.system76.gpu.mode = lib.mkOption {
  type = lib.types.enum [ "hybrid-sync" "nvidia-only" ];
  default = "hybrid-sync";
};

hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = true;
  open = false;  # Proprietary driver
};

# PRIME sync (default)
hardware.nvidia.prime = {
  sync.enable = true;
  intelBusId = "PCI:0:2:0";
  nvidiaBusId = "PCI:1:0:0";
};
```

| Mode          | Description                                               |
| ------------- | --------------------------------------------------------- |
| `hybrid-sync` | iGPU drives display, dGPU renders (battery + performance) |
| `nvidia-only` | Only dGPU active (maximum GPU performance)                |

## Boot Configuration

```nix
# modules/system76/boot.nix
boot = {
  kernelPackages = pkgs.linuxPackages_latest;
  blacklistedKernelModules = [ "nouveau" ];

  kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_EnableGpuFirmware=1"
  ];

  crashDump = {
    enable = true;
    reservedMemory = "512M";
  };

  kernel.sysctl = {
    "kernel.sysrq" = 1;
    "kernel.printk" = "7 4 1 7";
  };

  loader.systemd-boot = {
    enable = true;
    configurationLimit = 3;
  };
};
```

## Storage (LUKS)

```nix
# modules/system76/hardware-config.nix
boot.initrd.luks = {
  reusePassphrases = true;
  devices = {
    "luks-..." = { device = "/dev/disk/by-uuid/..."; };  # Root
    "luks-..." = { device = "/dev/disk/by-uuid/..."; };  # Swap
    "data" = { device = "..."; allowDiscards = true; };  # Data SSD
  };
};
```

| Mount   | Device   | Filesystem       |
| ------- | -------- | ---------------- |
| `/`     | NVMe     | ext4 (encrypted) |
| `/boot` | NVMe     | vfat             |
| `/data` | SATA SSD | XFS (encrypted)  |
| swap    | NVMe     | swap (encrypted) |

## Audio & Bluetooth

```nix
# Audio: PipeWire
services.pipewire = {
  enable = true;
  alsa.enable = true;
  pulse.enable = true;
};

# Bluetooth
hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;
};
```

## Unfree Packages

```nix
# modules/system76/packages.nix
nixpkgs.allowedUnfreePackages = [
  "nvidia-x11"
  "nvidia-settings"
  "system76-wallpapers"
  # ... other unfree packages
];
```

> **Note:** All firmware packages are redistributable, not unfree.

## System76 Tools

| Tool     | Command                               | Purpose                  |
| -------- | ------------------------------------- | ------------------------ |
| Power    | `system76-power profile <profile>`    | Power profile            |
| Battery  | `system76-power charge-thresholds`    | Battery charge limits    |
| Firmware | `sudo system76-firmware-cli schedule` | Schedule firmware update |
| Keyboard | `system76-keyboard-configurator`      | Keyboard customization   |

## Quick Reference

```bash
# Services
systemctl status com.system76.PowerDaemon
systemctl status system76-scheduler

# Power management
system76-power profile                   # Show current profile
system76-power charge-thresholds         # Show charge limits

# GPU
nvidia-smi
glxinfo | grep "OpenGL renderer"

# Firmware updates
fwupdmgr get-updates
sudo system76-firmware-cli schedule

# Rebuild
sudo nixos-rebuild switch --flake .#system76
```
