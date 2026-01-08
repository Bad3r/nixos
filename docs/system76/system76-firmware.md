# System76 Oryx Pro Firmware Guide

## Firmware Overview

This system uses **proprietary firmware** managed by System76. It does NOT use System76 Open Firmware (coreboot-based), which is only available on newer models (oryp6+).

## Current Firmware Versions

| Component   | Version              | Date                |
| ----------- | -------------------- | ------------------- |
| BIOS/UEFI   | 1.07.11RSA4-1        | 2018-12-04          |
| EC Firmware | Bundled with updates | Managed by System76 |

## Firmware Components

### BIOS/UEFI (`firmware.rom`)

The main system firmware responsible for:

- Hardware initialization
- Boot device selection
- UEFI settings and variables
- Power management tables (ACPI)

### Embedded Controller (`ec.rom`)

The EC firmware controls:

- **Fan speed curves** (hard-coded, not user-adjustable)
- Keyboard backlighting
- Battery charging
- Power button handling
- Fn key combinations (including Fn+1 for max fans)
- Temperature reporting to OS

> **Important:** EC firmware controls fan behavior. Updating EC firmware may change fan curves and thermal behavior.

## Checking Firmware Status

### Current Version

```bash
# BIOS version
cat /sys/class/dmi/id/bios_version
cat /sys/class/dmi/id/bios_date

# System identification
cat /sys/class/dmi/id/product_name

# fwupd device list
fwupdmgr get-devices
```

### Available Updates

```bash
# Check for updates via fwupd
fwupdmgr get-updates

# System76 firmware tool
system76-firmware-cli schedule
```

## Updating Firmware

### Prerequisites

1. **AC power required** - Do not update on battery
2. **Stable power** - Use UPS if available
3. **Close all applications** - Update runs during reboot
4. **Backup important data** - Firmware updates carry small risk

### Update Procedure

#### Method 1: System76 Firmware CLI (Recommended)

```bash
# Schedule firmware update
sudo system76-firmware-cli schedule

# Output will show:
# - Downloaded firmware package
# - Scheduled for next reboot
# - "Firmware update scheduled. Reboot your machine to install."

# Reboot to apply
sudo reboot
```

The system will:

1. Boot into firmware update environment
2. Flash BIOS and EC firmware
3. Automatically reboot into normal OS

#### Method 2: fwupdmgr

```bash
# Refresh metadata
fwupdmgr refresh

# Check for updates
fwupdmgr get-updates

# Apply updates (if available)
fwupdmgr update
```

### Post-Update Verification

```bash
# Check new BIOS version
cat /sys/class/dmi/id/bios_version

# Verify system stability
sensors
dmesg | grep -i firmware
```

## Firmware Update Contents

When running `system76-firmware-cli schedule`, the following files are downloaded:

| File             | Purpose                        |
| ---------------- | ------------------------------ |
| `firmware.rom`   | BIOS/UEFI image                |
| `ec.rom`         | Embedded Controller firmware   |
| `afuefi.efi`     | AMI flash utility              |
| `fpt.efi`        | Flash Programming Tool         |
| `uecflash.efi`   | EC flash utility               |
| `meset.efi`      | ME setup utility               |
| `changelog.json` | Version and change information |

Files are extracted to `/boot/system76-firmware-update/` and executed via EFI boot entry.

## Model Identification

The firmware system identifies this laptop as:

| Field          | Value              |
| -------------- | ------------------ |
| Firmware Model | `oryp4`            |
| Chassis        | `P950Ex`           |
| Transition     | `P950Ex -> P950Ex` |

> **Note:** Earlier documentation may reference `oryp3` (P650RS-G). The firmware detection shows `oryp4` (P950Ex) as the correct model identifier.

## UEFI/BIOS Settings

Access UEFI setup by pressing **F2** during boot.

### Recommended Settings

| Setting     | Value            | Reason                         |
| ----------- | ---------------- | ------------------------------ |
| Secure Boot | Enabled/Disabled | Per your security requirements |
| Boot Mode   | UEFI             | Required for NixOS             |
| Fast Boot   | Disabled         | Allows F2/F7 access            |
| Fan Mode    | Auto             | Let EC manage fans             |

### Boot Menu

Press **F7** during boot for one-time boot device selection.

## Troubleshooting

### Firmware Update Fails to Start

1. Verify update is scheduled:

   ```bash
   ls -la /boot/system76-firmware-update/
   ```

2. Check EFI boot entry:

   ```bash
   efibootmgr -v | grep system76
   ```

3. Ensure EFI partition is mounted:
   ```bash
   mount | grep /boot
   ```

### System Won't Boot After Update

1. **Wait** - First boot after update may take longer
2. Power cycle - Hold power button 10 seconds, then restart
3. Reset CMOS - Remove battery and AC, hold power 30 seconds
4. Recovery - Contact System76 support if system doesn't boot

### EC Firmware Issues

If fan behavior changes unexpectedly after update:

- EC firmware may have updated fan curves
- Monitor temperatures and fan behavior
- Report issues to System76 if fans don't respond properly

## Firmware Architecture

```
┌─────────────────────────────────────────┐
│              UEFI/BIOS                  │
│         (firmware.rom)                  │
├─────────────────────────────────────────┤
│     Intel Management Engine (ME)        │
│           (locked region)               │
├─────────────────────────────────────────┤
│      Embedded Controller (EC)           │
│           (ec.rom)                      │
│  - Fan control    - Power management    │
│  - Keyboard       - Fn keys             │
│  - Sensors        - Battery             │
└─────────────────────────────────────────┘
```

## Open Firmware Note

This system does **NOT** support System76 Open Firmware. Open Firmware (coreboot-based) is only available on:

- Oryx Pro 6+ (oryp6, oryp7, oryp8, etc.)
- Select other newer System76 models

See [System76 Open Firmware Systems](https://support.system76.com/articles/open-firmware-systems/) for supported models.

## Related Documentation

- [system76-overview.md](system76-overview.md) - Hardware overview
- [system76-thermal-management.md](system76-thermal-management.md) - Thermal configuration
- [system76-crash-diagnostics.md](system76-crash-diagnostics.md) - Crash analysis

## Resources

- [System76 Firmware Support](https://support.system76.com/articles/system-firmware/)
- [System76 Firmware GitHub](https://github.com/system76/firmware-update)
- [fwupd Documentation](https://fwupd.org/)
