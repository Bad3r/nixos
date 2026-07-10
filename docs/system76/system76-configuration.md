# System76 Oryx Pro NixOS Configuration

## Module Structure

All System76-specific configuration lives in `modules/system76/`:

| File                         | Purpose                                           |
| ---------------------------- | ------------------------------------------------- |
| `hardware-config.nix`        | Filesystems, LUKS, firmware, bluetooth, GPU mode  |
| `nvidia-gpu.nix`             | NVIDIA driver, PRIME sync/nvidia-only mode        |
| `boot.nix`                   | linux-zen kernel, crash dump, NVIDIA params       |
| `services.nix`               | power management, scheduler, logging              |
| `support.nix`                | System76 kernel modules, firmware daemon          |
| `system76-power-overlay.nix` | `system76-power` patch (skip non-ALPM SCSI hosts) |
| `packages.nix`               | System76 utilities, unfree allowlist              |

## Hardware Support

`support.nix` defines the `system76-support` NixOS module behind the
`hardware.system76.extended.enable` option. The host opts in from `imports.nix`:

```nix
# modules/system76/imports.nix
hardware.system76.extended.enable = true;
```

When enabled, the module turns on the System76 hardware stack:

```nix
# modules/system76/support.nix (effect of extended.enable)
hardware.system76 = {
  kernel-modules.enable = true;   # Fan monitoring, EC communication
  firmware-daemon.enable = true;  # Firmware updates via fwupd
  power-daemon.enable = true;     # Thermal management, power profiles, battery thresholds
};

boot.kernelParams = [ "system76_acpi.brightness_hwmon=1" ];
services.fwupd.enable = true;
```

## Hardware Firmware

The host declares the firmware it needs explicitly, layered on top of the
redistributable default via `lib.mkAfter`:

```nix
# modules/system76/hardware-config.nix
hardware.firmware = lib.mkAfter [
  pkgs.linux-firmware  # Intel 8265 WiFi/BT, i915 GPU
  pkgs.sof-firmware    # Intel audio DSP
  pkgs.wireless-regdb  # WiFi regulatory
];

# modules/base/hardware-scan.nix
hardware = {
  enableRedistributableFirmware = lib.mkDefault true;
  enableAllFirmware = false;
};
```

Intel CPU microcode is not set here; it is provided by the
`nixos-hardware` `common-cpu-intel-cpu-only` module imported in
`imports.nix`.

All firmware is redistributable (no unfree). See [system76-hardware.md](system76-hardware.md) for firmware details.

## Services

```nix
# modules/system76/services.nix
services = {
  # Thermal management via system76-power (hardware.system76.power-daemon)
  thermald.enable = false;

  system76-scheduler.enable = true;  # Desktop responsiveness
  power-profiles-daemon.enable = lib.mkForce false;  # Conflicts with system76-power
  lact.enable = true;  # GPU control/monitoring (power limits, fan curves, clocks)
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

Shared NVIDIA wiring (driver selection, open-module toggle, container
toolkit, VA-API routing, PRIME) lives in the parameterized
`flake.nixosModules.nvidia-gpu` module (`modules/hardware/nvidia-gpu.nix`).
The host file maps the `system76.gpu.mode` enum onto it and keeps the
chassis-specific libva routing.

```nix
# modules/system76/nvidia-gpu.nix
options.system76.gpu = {
  mode = lib.mkOption {
    type = lib.types.enum [ "hybrid-sync" "nvidia-only" ];
    default = "hybrid-sync";
  };
  intelBusId = lib.mkOption { type = lib.types.str; default = "PCI:0:2:0"; };
  nvidiaBusId = lib.mkOption { type = lib.types.str; default = "PCI:1:0:0"; };
};

gpu.nvidia = {
  enable = true;
  # GTX 1070 Max-Q is supported by the 580.xx legacy branch only.
  package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  open = false;                  # Pascal predates the open kernel modules
  vaapi.backend = "intel-media"; # VA-API routes to Intel iHD, not NVDEC (Xid 31)
  prime = {
    enable = cfg.mode == "hybrid-sync";
    inherit (cfg) intelBusId nvidiaBusId;
  };
};

# nvidia-only branch: libva uses Intel Quick Sync through the stable iGPU render node.
environment.sessionVariables.LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
environment.sessionVariables.LIBVA_DRM_DEVICE = lib.mkDefault "/dev/dri/by-path/pci-0000:00:02.0-render";
```

```nix
# Active host mode is set in hardware-config.nix (overrides the hybrid-sync default):
system76.gpu.mode = "nvidia-only";
```

| Mode          | Description                                                | Active                       |
| ------------- | ---------------------------------------------------------- | ---------------------------- |
| `hybrid-sync` | iGPU drives display, dGPU renders (battery + performance)  | option default               |
| `nvidia-only` | Only dGPU active, PRIME disabled (maximum GPU performance) | set in `hardware-config.nix` |

## Boot Configuration

```nix
# modules/system76/boot.nix
boot = {
  # linux-zen: low-latency desktop kernel, prebuilt in cache.nixos.org.
  kernelPackages = pkgs.linuxPackages_zen;
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
    "kernel.dmesg_restrict" = 0;  # Allow dmesg without sudo
  };
};

# The bootloader, LUKS devices, and filesystems live in hardware-config.nix:
# modules/system76/hardware-config.nix
boot.loader.systemd-boot = {
  enable = true;
  configurationLimit = 3;
};
```

## Storage (LUKS)

```nix
# modules/system76/hardware-config.nix
boot.initrd.luks = {
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
# Audio: PipeWire (modules/hosts/common/pipewire.nix)
services.pipewire = {
  enable = true;
  alsa.enable = true;
  alsa.support32Bit = true;
  pulse.enable = true;
};

# Bluetooth (modules/system76/hardware-config.nix)
hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;
  settings.General = {
    Experimental = true;        # battery-level reporting
    KernelExperimental = true;
  };
};
```

## Unfree Packages

```nix
# modules/system76/packages.nix - System76-branded artwork only
nixpkgs.allowedUnfreePackages = [
  "system76-wallpapers"
  "system76-wallpapers-0-unstable-2024-04-26"
];
```

NVIDIA unfree entries (`nvidia-kernel-modules`, `nvidia-x11`,
`nvidia-settings`) are allowed in the shared
`modules/hosts/common/packages.nix` allowlist, not in the System76 module.
`imports.nix` additionally allows `p7zip-rar`, `rar`, and `unrar`.

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
# Services (unit is system76-power.service; com.system76.PowerDaemon is its D-Bus name)
systemctl status system76-power
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
