# System76 Oryx Pro NixOS Configuration

This document describes the NixOS configuration for the System76 Oryx Pro laptop, including System76-specific software, services, and hardware support modules.

## Module Structure

All System76-specific configuration lives in `modules/system76/`. Key files:

| File                   | Purpose                                                     |
| ---------------------- | ----------------------------------------------------------- |
| `support.nix`          | System76 hardware support (kernel modules, firmware daemon) |
| `services.nix`         | System services (thermald, scheduler, logging)              |
| `packages.nix`         | System76 utilities and diagnostic tools                     |
| `boot.nix`             | Kernel configuration, crash dump, NVIDIA params             |
| `nvidia-gpu.nix`       | NVIDIA GPU configuration (PRIME sync/offload)               |
| `graphics-support.nix` | Graphics libraries (Mesa, VA-API, VDPAU)                    |
| `hardware-config.nix`  | Hardware-specific config (filesystems, LUKS, bluetooth)     |
| `thermald.conf.xml`    | Custom thermald configuration                               |

## System76 Software Stack

### Installed Packages

```nix
# modules/system76/packages.nix
environment.systemPackages = [
  # System76 utilities
  system76-power          # Power management CLI
  system76-scheduler      # Process scheduler
  system76-firmware       # Firmware update CLI
  system76-wallpapers     # Branded wallpapers
  firmware-manager        # GUI firmware updater
  system76-keyboard-configurator  # Keyboard customization

  # Diagnostic tools
  lm_sensors              # Temperature/fan monitoring
  smartmontools           # Storage health
  nvme-cli                # NVMe diagnostics
  stress-ng               # Stress testing
  memtester               # Memory testing
  glmark2                 # GPU benchmarking
  hwinfo                  # Hardware info
];
```

### System76 CLI Tools

| Tool                    | Command                          | Purpose                       |
| ----------------------- | -------------------------------- | ----------------------------- |
| `system76-power`        | `system76-power profile`         | View/set power profile        |
| `system76-firmware-cli` | `system76-firmware-cli schedule` | Schedule firmware updates     |
| `firmware-manager`      | GUI                              | Graphical firmware management |

### Tool Usage Examples

```bash
# Check power profile
system76-power profile

# Set power profile
system76-power profile performance
system76-power profile balanced
system76-power profile battery

# Schedule firmware update
sudo system76-firmware-cli schedule
```

## Hardware Support Configuration

### System76 Hardware Module

```nix
# modules/system76/support.nix
hardware.system76 = {
  kernel-modules.enable = true;   # Fan monitoring, EC communication
  firmware-daemon.enable = true;  # Firmware updates via fwupd/LVFS
  power-daemon.enable = false;    # DISABLED - using thermald instead
};

# System76-specific kernel parameters
boot.kernelParams = [ "system76_acpi.brightness_hwmon=1" ];

# Enable LVFS firmware updates
services.fwupd.enable = true;
```

### Why power-daemon is Disabled

The System76 power daemon (`system76-power`) is disabled because:

1. **EC over-reports temperatures** by ~5C
2. This causes **premature thermal throttling**
3. **thermald** with `x86_pkg_temp` provides accurate readings
4. See [system76-thermal-management.md](system76-thermal-management.md)

## Services Configuration

### Core Services

```nix
# modules/system76/services.nix
services = {
  # Thermal management (replaces system76-power thermal handling)
  thermald = {
    enable = true;
    debug = true;
    configFile = ./thermald.conf.xml;
  };

  # System76 process scheduler
  # Adjusts CFS latency, boosts foreground processes
  system76-scheduler.enable = true;

  # GPU control and monitoring
  lact.enable = true;

  # Power management
  upower.enable = true;
  power-profiles-daemon.enable = false;  # Conflicts with thermald

  # Persistent logging for crash analysis
  journald = {
    storage = "persistent";
    extraConfig = ''
      SystemMaxUse=1G
      SystemKeepFree=10%
    '';
  };

  # SSD maintenance
  fstrim.enable = true;

  # File indexing
  locate = {
    enable = true;
    package = pkgs.plocate;
  };
};

# Performance CPU governor
powerManagement.cpuFreqGovernor = "performance";

# Disable CoolerControl (conflicts with EC)
programs.coolercontrol.enable = false;
```

### System76 Scheduler

The `system76-scheduler` service improves desktop responsiveness:

- Adjusts CFS (Completely Fair Scheduler) latency
- Boosts priority of foreground/focused applications
- Different tuning for AC vs battery power

```bash
# Check scheduler status
systemctl status system76-scheduler
```

### LACT GPU Control

LACT provides GPU monitoring and control:

```bash
# Launch LACT GUI
lact gui

# CLI usage
lact info
lact --help
```

## Boot Configuration

### Kernel Setup

```nix
# modules/system76/boot.nix
boot = {
  # Latest kernel
  kernelPackages = pkgs.linuxPackages_latest;

  # Hardware modules
  initrd.availableKernelModules = [
    "xhci_pci" "ahci" "nvme" "thunderbolt"
    "usbhid" "uas" "usb_storage" "sd_mod" "sdhci_pci"
  ];

  kernelModules = [ "kvm-intel" ];

  # Blacklist nouveau for NVIDIA
  blacklistedKernelModules = [ "nouveau" ];

  # NVIDIA kernel parameters
  kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_EnableGpuFirmware=1"
  ];

  # Crash dump support
  crashDump = {
    enable = true;
    reservedMemory = "512M";
  };

  # Debug settings
  kernel.sysctl = {
    "kernel.printk" = "7 4 1 7";  # Verbose logging
    "kernel.sysrq" = 1;           # Magic SysRq
    "kernel.dmesg_restrict" = 0;  # dmesg without sudo
  };
};
```

### Boot Loader

```nix
boot.loader = {
  systemd-boot = {
    enable = true;
    editor = false;
    consoleMode = "auto";
    configurationLimit = 3;
  };
  efi.canTouchEfiVariables = true;
};
```

## NVIDIA GPU Configuration

### GPU Modes

```nix
# modules/system76/nvidia-gpu.nix
options.system76.gpu = {
  mode = lib.mkOption {
    type = lib.types.enum [ "hybrid-sync" "nvidia-only" ];
    default = "hybrid-sync";
  };
  intelBusId = lib.mkOption { default = "PCI:0:2:0"; };
  nvidiaBusId = lib.mkOption { default = "PCI:1:0:0"; };
};
```

| Mode          | Description                                    | Use Case                   |
| ------------- | ---------------------------------------------- | -------------------------- |
| `hybrid-sync` | PRIME sync - iGPU drives display, dGPU renders | Battery life + performance |
| `nvidia-only` | Only dGPU active, iGPU disabled                | Maximum GPU performance    |

### Current Configuration

```nix
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = true;
  powerManagement.finegrained = false;  # Incompatible with PRIME sync
  open = false;                         # Use proprietary driver
  nvidiaSettings = true;                # Enable nvidia-settings
};

# PRIME sync (default)
hardware.nvidia.prime = {
  sync.enable = true;
  intelBusId = "PCI:0:2:0";
  nvidiaBusId = "PCI:1:0:0";
};

# Tear-free rendering
services.xserver.screenSection = ''
  Option "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
'';
```

### Checking GPU Status

```bash
# NVIDIA GPU info
nvidia-smi

# Check PRIME status
glxinfo | grep "OpenGL renderer"

# Vulkan info
vulkaninfo --summary

# PCI device info
lspci | grep -E "VGA|3D"
```

## Graphics Support

### Libraries

```nix
# modules/system76/graphics-support.nix
hardware.graphics = {
  enable = true;
  enable32Bit = true;
  extraPackages = with pkgs; [
    mesa libva libvdpau libglvnd
    nvidia-vaapi-driver
    vulkan-validation-layers
  ];
};
```

### Diagnostic Tools

```bash
# VA-API status
vainfo

# VDPAU status
vdpauinfo

# OpenGL info
glxinfo | head -20

# Vulkan info
vulkaninfo --summary
```

## Storage Configuration

### Encrypted Volumes (LUKS)

```nix
# modules/system76/hardware-config.nix
boot.initrd.luks = {
  reusePassphrases = true;  # Single passphrase for all volumes
  devices = {
    "luks-251cdcdc-..." = { device = "/dev/disk/by-uuid/..."; };  # Root
    "luks-42ddd341-..." = { device = "/dev/disk/by-uuid/..."; };  # Swap
    "data" = {
      device = "/dev/disk/by-uuid/183d1f98-...";
      allowDiscards = true;  # TRIM for SSD
    };
  };
};
```

### Filesystems

| Mount   | Device   | Filesystem | Notes                   |
| ------- | -------- | ---------- | ----------------------- |
| `/`     | NVMe     | ext4       | Root (encrypted)        |
| `/boot` | NVMe     | vfat       | EFI partition           |
| `/data` | SATA SSD | XFS        | Data volume (encrypted) |
| swap    | NVMe     | swap       | Encrypted swap          |

## Audio Configuration

### PipeWire Setup

```nix
# modules/system76/pipewire.nix
services.pipewire = {
  enable = true;
  alsa = {
    enable = true;
    support32Bit = true;
  };
  pulse.enable = true;
};

security.rtkit.enable = true;  # Real-time scheduling
```

### Audio Tools

```bash
# PulseAudio volume control
pavucontrol

# PipeWire graph (connections)
qpwgraph
helvum

# ALSA utilities
alsamixer
aplay -l  # List devices
```

### Sound Firmware

```nix
# Intel Sound Open Firmware for Cannon Lake DSP
hardware.firmware = [ pkgs.sof-firmware ];
```

## Bluetooth Configuration

```nix
# modules/system76/bluetooth.nix
hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;
  settings.General = {
    Experimental = true;
    KernelExperimental = true;
  };
};

# TUI bluetooth manager
environment.systemPackages = [ pkgs.bluetui ];
```

### Bluetooth Commands

```bash
# TUI manager
bluetui

# CLI
bluetoothctl
  > power on
  > scan on
  > pair XX:XX:XX:XX:XX:XX
  > connect XX:XX:XX:XX:XX:XX
```

## Nix Configuration

```nix
# modules/system76/nix-settings.nix
nix = {
  settings = {
    experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
    auto-optimise-store = true;
    cores = 0;              # Use all cores
    max-jobs = "auto";
    min-free = 53687091200; # 50GB - trigger GC when less
  };

  gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
};
```

## TCC Offset Configuration

```nix
# Set TCC offset to 0 (allow CPU to reach 100C)
systemd.tmpfiles.rules = [
  "w /sys/class/thermal/cooling_device13/cur_state - - - - 0"
];
```

This allows the CPU to use its full thermal headroom. Combined with thermald at 85C/92C trip points, the CPU stays well below 100C under normal operation.

## Input Configuration

### Touchpad

```nix
services.libinput = {
  enable = true;
  touchpad = {
    tapping = true;
    middleEmulation = true;
    naturalScrolling = true;
  };
};
```

### Power Button

```nix
# Ignore power button (prevent accidental shutdown)
services.logind.settings.Login.HandlePowerKey = "ignore";
```

## Firmware Manager Fix

```nix
# modules/system76/firmware-manager-fix.nix
# Overlay to fix firmware-manager build
nixpkgs.overlays = [
  (_final: prev: {
    firmware-manager = prev.firmware-manager.overrideAttrs (oldAttrs: {
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
        prev.pkg-config
      ];
      buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
        prev.xz  # Provides liblzma
      ];
      PKG_CONFIG_PATH = "${prev.xz.dev}/lib/pkgconfig";
    });
  })
];
```

## Quick Reference Commands

### System76 Tools

```bash
# Power profile
system76-power profile
system76-power profile performance

# Firmware update
sudo system76-firmware-cli schedule

# Keyboard configurator
system76-keyboard-configurator
```

### Hardware Monitoring

```bash
# All sensors
sensors

# Fan status
sensors system76-isa-0000

# GPU status
nvidia-smi

# Storage health
sudo smartctl -a /dev/nvme0
sudo nvme smart-log /dev/nvme0
```

### Service Status

```bash
# thermald
systemctl status thermald
journalctl -u thermald -f

# System76 scheduler
systemctl status system76-scheduler

# fwupd
fwupdmgr get-devices
fwupdmgr get-updates
```

## Related Documentation

- [system76-overview.md](system76-overview.md) - Hardware overview
- [system76-thermal-management.md](system76-thermal-management.md) - Thermal configuration
- [system76-fan-replacement.md](system76-fan-replacement.md) - Fan replacement
- [system76-firmware.md](system76-firmware.md) - Firmware management
- [system76-crash-diagnostics.md](system76-crash-diagnostics.md) - Crash analysis
