# System76 Oryx Pro Hardware Overview

## System Identification

| Property          | Value    |
| ----------------- | -------- |
| System76 Model    | Oryx Pro |
| Internal Codename | `oryp4`  |
| Clevo Chassis     | P950Ex   |
| Product Name      | Oryx Pro |

> **Note:** The system firmware identifies as `oryp4` (P950Ex), though earlier documentation may reference `oryp3` (P650RS-G). The P950Ex is the correct chassis identification based on firmware detection.

## Hardware Specifications

### CPU

| Property      | Value               |
| ------------- | ------------------- |
| Model         | Intel Core i7-8750H |
| Codename      | Coffee Lake         |
| Cores/Threads | 6C/12T              |
| Base Clock    | 2.20 GHz            |
| Turbo Clock   | 4.10 GHz            |
| TDP           | 45W                 |
| Tjmax         | 100C                |
| Microcode     | 0x000000fa          |

### Chipset

| Component | Value                      |
| --------- | -------------------------- |
| PCH       | Intel Cannon Lake          |
| Sensor    | `pch_cannonlake-virtual-0` |

### Storage

| Device | Model           | Capacity |
| ------ | --------------- | -------- |
| NVMe   | Samsung 970 PRO | 512GB    |
| SATA   | Samsung 860 PRO | 2TB      |

### Graphics

| Type       | Details                                       |
| ---------- | --------------------------------------------- |
| Integrated | Intel UHD 630                                 |
| Discrete   | NVIDIA GTX 10-series (model varies by config) |

## Firmware

| Component   | Version             | Date                |
| ----------- | ------------------- | ------------------- |
| BIOS/UEFI   | 1.07.11RSA4-1       | 2018-12-04          |
| EC Firmware | Managed by System76 | See firmware update |

See [system76-firmware.md](system76-firmware.md) for update procedures.

## Thermal Sensors

### Available Sensors

```
coretemp-isa-0000        # Per-core CPU temperatures
pch_cannonlake-virtual-0 # Platform Controller Hub
system76-isa-0000        # System76 EC sensors (CPU/GPU temp, fans)
```

### Sensor Mapping

| Sensor            | Source        | Notes                               |
| ----------------- | ------------- | ----------------------------------- |
| `x86_pkg_temp`    | CPU package   | Primary thermal zone for throttling |
| `pch_cannonlake`  | PCH           | I/O controller, typically 50-60C    |
| `CPU temperature` | EC (system76) | Over-reports by ~5C                 |
| `GPU temperature` | EC (system76) | May read 0C when idle               |

### Monitoring Commands

```bash
# All sensors
sensors

# System76 EC sensors (fans + temps)
sensors system76-isa-0000

# CPU core temperatures
sensors coretemp-isa-0000

# Continuous monitoring
watch -n 1 sensors
```

## Cooling System

| Component      | Details                              |
| -------------- | ------------------------------------ |
| Configuration  | Dual-fan with shared heatsink        |
| CPU Fan        | DFS541105FC0T-FGFG                   |
| GPU Fan        | DFS541105FC0T-FGFF                   |
| Fan Control    | EC-controlled (no software override) |
| Max Fan Hotkey | Fn+1                                 |

See [system76-fan-replacement.md](system76-fan-replacement.md) for replacement parts.

## Known Issues

### EC Temperature Over-Reporting

The System76 Embedded Controller reports temperatures approximately 5C higher than actual. This can cause:

- Premature thermal throttling
- Unexpected shutdowns if using EC readings for thermal management

**Mitigation:** Use Intel thermald with `x86_pkg_temp` sensor instead of EC readings.

### Fan Control Limitations

- EC firmware has hard-coded fan curves
- Software fan control (PWM writes) does not persist - EC overrides immediately
- CoolerControl and similar tools conflict with EC, causing system instability

### Fan Failure Crash

If one fan in the dual-fan assembly fails, pressing Fn+1 (max fan speed) will crash the system. This occurs even in BIOS, confirming hardware-level failure.

See [system76-crash-diagnostics.md](system76-crash-diagnostics.md) for diagnostic procedures.

## Related Documentation

- [system76-thermal-management.md](system76-thermal-management.md) - Thermal configuration and thermald setup
- [system76-fan-replacement.md](system76-fan-replacement.md) - Fan replacement parts and procedures
- [system76-firmware.md](system76-firmware.md) - Firmware versions and update procedures
- [system76-crash-diagnostics.md](system76-crash-diagnostics.md) - Crash analysis and diagnostics
