# System76 Oryx Pro Hardware Reference

## System Identification

| Property | Value |
|----------|-------|
| Model | Oryx Pro (oryp4) |
| Chassis | Clevo P950Ex |
| BIOS | 1.07.11RSA4-1 (2018-12-04) |

## Hardware Specifications

### CPU

| Property | Value |
|----------|-------|
| Model | Intel Core i7-8750H (Coffee Lake) |
| Cores/Threads | 6C/12T |
| Base/Turbo | 2.20 / 4.10 GHz |
| TDP | 45W |
| Tjmax | 100C |

### Graphics

| Type | Model | Driver |
|------|-------|--------|
| iGPU | Intel UHD 630 | i915 |
| dGPU | NVIDIA GTX 10-series | nvidia (proprietary) |

### Storage

| Device | Model | Capacity |
|--------|-------|----------|
| NVMe | Samsung 970 PRO | 512GB |
| SATA | Samsung 860 PRO | 2TB |

### Wireless

| Component | Model | Firmware |
|-----------|-------|----------|
| WiFi | Intel 8265 | `8265-36.ucode` |
| Bluetooth | Intel 8265 (combo) | `intel/ibt-12-16.sfi` |

> **Note:** WiFi and Bluetooth are a single Intel 8265 combo card.

## Cooling System

### Configuration

| Component | Details |
|-----------|---------|
| Design | Dual-fan with shared heatsink |
| Control | EC-managed (no software override) |
| Max Fan Hotkey | Fn+1 |

### Fan Identification

| Position | Model | Part Number |
|----------|-------|-------------|
| CPU | FGFG | DFS541105FC0T-FGFG |
| GPU | FGFF | DFS541105FC0T-FGFF |

Both fans are a unified assembly (part `6-31-P65S2-103`) and must be replaced together.

```
┌─────────────────────────────────────┐
│     Heatsink (copper heatpipes)     │
├─────────────────────────────────────┤
│  ┌─────────┐           ┌─────────┐  │
│  │ GPU Fan │◄─────────►│ CPU Fan │  │
│  │  FGFF   │  Heatpipe │  FGFG   │  │
│  └─────────┘           └─────────┘  │
└─────────────────────────────────────┘
```

## Thermal Sensors

### Available Sensors

```bash
sensors                        # All sensors
sensors coretemp-isa-0000      # CPU core temps (accurate)
sensors system76-isa-0000      # EC sensors (fans, temps)
```

### Sensor Mapping

| Sensor | Source | Notes |
|--------|--------|-------|
| `coretemp` / `x86_pkg_temp` | CPU | Accurate, use for thermal management |
| `pch_cannonlake` | PCH | I/O controller, typically 50-60C |
| `system76` CPU temp | EC | Over-reports by ~5C |
| `system76` GPU temp | EC | May read 0C when idle |

## Firmware

### System76 Firmware (BIOS/EC)

| Component | Description |
|-----------|-------------|
| BIOS/UEFI | Hardware init, boot, ACPI |
| EC | Fan curves, keyboard, battery, Fn keys |

#### Checking Current Version

```bash
cat /sys/class/dmi/id/bios_version    # BIOS version
cat /sys/class/dmi/id/bios_date       # BIOS date
fwupdmgr get-devices                   # All firmware devices
```

#### Update via System76 CLI (Recommended)

```bash
# Check for and schedule update
sudo system76-firmware-cli schedule

# Reboot to apply
sudo reboot
# System boots into firmware update, then reboots to OS
```

#### Update via fwupdmgr

```bash
# Refresh firmware metadata
fwupdmgr refresh

# Check for updates
fwupdmgr get-updates

# Apply updates
fwupdmgr update

# Reboot to apply
sudo reboot
```

#### Prerequisites

- AC power connected (do not update on battery)
- Close all applications
- Backup important data

### Linux Firmware (NixOS-managed)

Verified via `dmesg | grep -i firmware`:

| Component | Firmware | Package |
|-----------|----------|---------|
| Intel WiFi | `8265-36.ucode` | `linux-firmware` |
| Intel Bluetooth | `intel/ibt-12-16.sfi` | `linux-firmware` |
| Intel iGPU | `i915/kbl_dmc_ver1_04.bin` | `linux-firmware` |
| Intel Audio | SOF (fallback) | `sof-firmware` |
| Intel CPU | microcode | `hardware.cpu.intel.updateMicrocode` |
| NVIDIA GPU | bundled | nvidia driver |

## Quick Commands

```bash
# Hardware info
lspci | grep -E "VGA|3D|Network|Audio"
lsusb

# Sensors
sensors
watch -n 1 sensors

# GPU
nvidia-smi
glxinfo | grep "OpenGL renderer"

# Storage
sudo smartctl -a /dev/nvme0
sudo nvme smart-log /dev/nvme0

# Firmware
cat /sys/class/dmi/id/bios_version
fwupdmgr get-devices
```
