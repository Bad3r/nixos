# System76 Oryx Pro Thermal Management

## Overview

This system uses **Intel thermald** for thermal management instead of the default System76 power daemon. This configuration addresses the EC temperature over-reporting issue and provides more reliable thermal throttling.

## Why thermald Instead of system76-power?

| Aspect             | system76-power                | thermald                   |
| ------------------ | ----------------------------- | -------------------------- |
| Temperature Source | EC sensors (over-reports ~5C) | x86_pkg_temp (accurate)    |
| Throttling Method  | EC-controlled                 | RAPL, powerclamp, P-states |
| Configuration      | Hard-coded in EC              | Customizable XML config    |
| Fan Control        | EC-managed fan curves         | Does not control fans      |

**Key Issue:** The System76 EC over-reports temperatures by approximately 5C, causing premature throttling and potential unexpected shutdowns when using EC-based thermal management.

## NixOS Configuration

### Module Location

```
modules/system76/services.nix
```

### Key Settings

```nix
services = {
  # Disable system76-power thermal management
  # (keep firmware-daemon and kernel-modules enabled)

  # Enable thermald with custom config
  thermald = {
    enable = true;
    debug = true;  # Enable for troubleshooting
    configFile = ./thermald.conf.xml;
  };

  # Disable conflicting services
  power-profiles-daemon.enable = lib.mkForce false;
};

# Performance CPU governor
powerManagement.cpuFreqGovernor = "performance";

# Set TCC offset to 0 (allow CPU to reach Tjmax 100C)
systemd.tmpfiles.rules = [
  "w /sys/class/thermal/cooling_device13/cur_state - - - - 0"
];

# Disable CoolerControl (conflicts with EC fan control)
programs.coolercontrol.enable = false;
```

## thermald Configuration

### Config File Location

```
modules/system76/thermald.conf.xml
```

### Configuration Explained

```xml
<ThermalConfiguration>
  <Platform>
    <Name>System76 Oryx Pro</Name>
    <ProductName>*</ProductName>
    <Preference>PERFORMANCE</Preference>

    <ThermalSensors>
      <ThermalSensor>
        <Type>x86_pkg_temp</Type>
        <AsyncCapable>1</AsyncCapable>
      </ThermalSensor>
    </ThermalSensors>

    <ThermalZones>
      <ThermalZone>
        <Type>x86_pkg_temp</Type>
        <TripPoints>
          <!-- 85C: Sequential throttling -->
          <TripPoint>
            <Temperature>85000</Temperature>
            <type>passive</type>
            <ControlType>SEQUENTIAL</ControlType>
            <!-- Cooling devices in order of application -->
          </TripPoint>

          <!-- 92C: Aggressive parallel throttling -->
          <TripPoint>
            <Temperature>92000</Temperature>
            <type>passive</type>
            <ControlType>PARALLEL</ControlType>
          </TripPoint>
        </TripPoints>
      </ThermalZone>
    </ThermalZones>
  </Platform>
</ThermalConfiguration>
```

### Trip Points

| Temperature | Mode       | Action                                   |
| ----------- | ---------- | ---------------------------------------- |
| 85C         | Sequential | Apply cooling methods one at a time      |
| 92C         | Parallel   | Apply all cooling methods simultaneously |

### Cooling Methods (in order of priority)

1. **RAPL Controller** - Intel Running Average Power Limit
   - Reduces CPU power budget
   - Fastest response, minimal performance impact

2. **Intel Powerclamp** - CPU idle injection
   - Forces CPU idle states
   - Moderate performance impact

3. **cpufreq** - P-state throttling
   - Reduces CPU frequency
   - Last resort, most noticeable impact

## TCC Offset

The Thermal Control Circuit (TCC) offset determines when hardware throttling begins relative to Tjmax (100C for this CPU).

| Setting   | Throttle Point | Purpose                     |
| --------- | -------------- | --------------------------- |
| Offset 0  | 100C           | Allow full thermal headroom |
| Offset 5  | 95C            | Default, conservative       |
| Offset 10 | 90C            | More aggressive throttling  |

**Current Setting:** Offset 0 (throttle at 100C)

This is necessary because the EC over-reports temperatures. With accurate x86_pkg_temp readings and thermald managing throttling at 85C/92C, the CPU will never actually reach 100C under normal operation.

### Verifying TCC Offset

```bash
# Check current TCC offset
cat /sys/class/thermal/cooling_device13/cur_state

# Should output: 0
```

## Monitoring

### Real-time Temperature Monitoring

```bash
# All thermal data
watch -n 1 sensors

# CPU package temperature (accurate)
watch -n 1 'sensors coretemp-isa-0000 | grep Package'

# thermald status
sudo systemctl status thermald
```

### thermald Debug Logging

With `debug = true`, thermald logs detailed information:

```bash
# View thermald logs
journalctl -u thermald -f

# Check trip point activations
journalctl -u thermald | grep -i "trip\|cool"
```

### Key Metrics to Watch

| Metric      | Normal Range | Warning        |
| ----------- | ------------ | -------------- |
| CPU Package | 40-85C       | >90C sustained |
| PCH         | 45-65C       | >80C           |
| Fan RPM     | 2000-4500    | 0 or erratic   |

## Fan Behavior

**Important:** thermald does NOT control fans. Fan control remains with the EC firmware.

| Temperature  | Expected Fan Behavior  |
| ------------ | ---------------------- |
| < 50C        | Low RPM or off         |
| 50-70C       | Moderate RPM           |
| 70-85C       | Higher RPM             |
| > 85C        | High RPM               |
| Fn+1 pressed | Maximum RPM (all fans) |

### Fan Control Limitations

- EC has hard-coded fan curves in firmware
- Software PWM writes are immediately overridden by EC
- CoolerControl and similar tools cause system instability
- Only reliable manual control: Fn+1 hotkey for max speed

## Troubleshooting

### thermald Not Throttling

1. Check if thermald is running:

   ```bash
   systemctl status thermald
   ```

2. Verify config is loaded:

   ```bash
   journalctl -u thermald | grep -i "config\|zone"
   ```

3. Check thermal zones:
   ```bash
   ls /sys/class/thermal/
   cat /sys/class/thermal/thermal_zone*/type
   ```

### High Temperatures Despite thermald

1. Verify TCC offset is 0:

   ```bash
   cat /sys/class/thermal/cooling_device13/cur_state
   ```

2. Check if fans are working:

   ```bash
   sensors system76-isa-0000 | grep fan
   ```

3. Consider thermal paste replacement if temps exceed 95C under moderate load

### System Crashes at High Temp

See [system76-crash-diagnostics.md](system76-crash-diagnostics.md) - crashes may be fan-related, not thermal.

## Related Documentation

- [system76-overview.md](system76-overview.md) - Hardware overview
- [system76-fan-replacement.md](system76-fan-replacement.md) - Fan replacement
- [system76-crash-diagnostics.md](system76-crash-diagnostics.md) - Crash analysis
