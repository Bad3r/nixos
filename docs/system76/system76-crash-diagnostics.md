# System76 Oryx Pro Crash Diagnostics

This guide documents crash investigation procedures, known crash causes, and the diagnostic instrumentation built into the system76 host profile.

---

## Known Crash Causes

### 1. Fan Failure Crash (CONFIRMED)

**Symptoms:**

- System crashes when pressing Fn+1 (max fan speed)
- Crash occurs even in BIOS (before OS loads)
- Crash happens regardless of temperature (tested at 57C)
- No kernel panic or error logged - abrupt power off

**Root Cause:**
One fan in the dual-fan assembly has failed. When Fn+1 commands both fans to 100% speed, the failed fan cannot comply. The EC detects the failure (0 RPM or timeout) and triggers a protective shutdown.

**Diagnosis:**

```bash
# Monitor both fans before triggering Fn+1
while true; do
  echo "$(date +%H:%M:%S) CPU:$(cat /sys/class/hwmon/hwmon7/fan1_input) GPU:$(cat /sys/class/hwmon/hwmon7/fan2_input)" >> ~/fan_log.txt
  sleep 0.5
done

# After crash, check which fan showed issues
cat ~/fan_log.txt | tail -20
```

**Resolution:**
Replace the dual-fan assembly. See [system76-fan-replacement.md](system76-fan-replacement.md).

**Workaround:**
Avoid pressing Fn+1. Let thermald manage thermal throttling instead.

### 2. CoolerControl/EC Conflict Crash

**Symptoms:**

- System crashes when CoolerControl is running
- Crash triggered by Fn+1 while CoolerControl active
- EC hangs causing system freeze

**Root Cause:**
CoolerControl and the EC both try to control fans simultaneously. When Fn+1 is pressed, the EC attempts to take control, but CoolerControl interference causes the EC to hang.

**Resolution:**

```nix
# In NixOS configuration
programs.coolercontrol.enable = false;
```

**Reference:** [system76-dkms issue #11](https://github.com/pop-os/system76-dkms/issues/11)

### 3. Thermal Shutdown (EC Over-Reporting)

**Symptoms:**

- Unexpected shutdown during heavy load
- x86_pkg_temp shows lower temperature than EC reports
- system76-power triggers shutdown prematurely

**Root Cause:**
System76 EC over-reports temperatures by approximately 5C, causing premature thermal protection.

**Resolution:**
Use thermald with x86_pkg_temp instead of system76-power. See [system76-thermal-management.md](system76-thermal-management.md).

---

## Diagnostic Configuration

### Module Locations

- `modules/system76/boot.nix` - Crash dump kernel configuration
- `modules/system76/services.nix` - Persistent journaling, coredump settings
- `modules/system76/packages.nix` - Diagnostic tools

### Key Settings

```nix
# Crash kernel reservation (512 MiB)
boot.crashDump.enable = true;

# Enable SysRq for manual dumps
boot.kernel.sysctl."kernel.sysrq" = 1;

# Verbose kernel logging
boot.kernel.sysctl."kernel.printk" = "7 4 1 7";

# Persistent journaling
services.journald.storage = "persistent";

# Systemd coredump
systemd.coredump.enable = true;
```

### Diagnostic Tools Available

| Tool            | Purpose                        |
| --------------- | ------------------------------ |
| `lm_sensors`    | Temperature and fan monitoring |
| `smartmontools` | Storage health (smartctl)      |
| `nvme-cli`      | NVMe diagnostics               |
| `stress-ng`     | CPU/memory stress testing      |
| `memtester`     | Memory testing                 |
| `glmark2`       | GPU stress testing             |
| `hwinfo`        | Hardware information           |

---

## Verifying Instrumentation

After rebuilding with diagnostic configuration:

### 1. Confirm Persistent Journaling

```bash
sudo journalctl --list-boots
# Should show multiple boot IDs without rotation warnings
```

### 2. Check Crash Kernel

```bash
# Verify crashkernel parameter
cat /proc/cmdline | tr ' ' '\n' | grep crashkernel

# Check crash kernel loaded
sudo journalctl -b | grep -F "loading crashdump kernel" -m1

# Verify kdump ready
sudo kdumpctl status
# Should report "Ready to kdump"
```

### 3. Validate SysRq and Logging

```bash
sudo sysctl kernel.sysrq           # Expect: 1
sudo sysctl kernel.printk          # Expect: 7 4 1 7
```

---

## When a Crash Occurs

### Immediate Actions

1. **If crash kernel boots** (rescue shell):

   ```bash
   makedumpfile -c --message-level 1 \
     --output /var/crash/$(date +%F-%H%M%S).vmcore.zst \
     /proc/vmcore
   sync
   reboot -f
   ```

2. **After normal reboot**, collect evidence:

   ```bash
   # Create logs directory
   mkdir -p ~/crash-logs

   # Kernel log from crashed boot
   sudo journalctl -b -1 -k > ~/crash-logs/kernel-$(date +%F-%H%M%S).log

   # Full journal from crashed boot
   sudo journalctl -b -1 > ~/crash-logs/journal-$(date +%F-%H%M%S).log
   ```

3. **Capture hardware telemetry**:

   ```bash
   # Storage health
   sudo smartctl -x /dev/nvme0 > ~/crash-logs/smart-$(date +%F-%H%M%S).txt
   sudo nvme smart-log /dev/nvme0 >> ~/crash-logs/smart-$(date +%F-%H%M%S).txt

   # Thermal state
   sensors > ~/crash-logs/sensors-$(date +%F-%H%M%S).txt

   # System info
   sudo dmesg > ~/crash-logs/dmesg-$(date +%F-%H%M%S).txt
   ```

4. **Record context**:
   - Time of crash
   - What was running (workload)
   - Power state (AC/battery)
   - Any Fn keys pressed
   - Temperature at time of crash (if known)

---

## Stress Testing Procedures

### CPU Stress Test

```bash
# Monitor in one terminal
watch -n 1 sensors

# Run stress in another
stress-ng --cpu $(nproc) --timeout 10m
```

### Memory Test

```bash
# Test 8GB for 1 pass
memtester 8192 1
```

### GPU Stress Test

```bash
# OpenGL benchmark
glmark2

# NVIDIA monitoring (if applicable)
nvidia-smi -l 1
```

### Combined Stress (Caution: May trigger crashes)

```bash
stress-ng --cpu 12 --vm 4 --vm-bytes 2G --timeout 10m
```

### Fan Failure Test (DANGEROUS)

Only if you suspect fan failure and accept crash risk:

```bash
# Start logging
while true; do
  echo "$(date +%H:%M:%S) CPU:$(cat /sys/class/hwmon/hwmon7/fan1_input) GPU:$(cat /sys/class/hwmon/hwmon7/fan2_input)"
  sleep 0.5
done | tee ~/fan_test.log

# In another terminal or via Fn key, trigger max fans
# WARNING: System may crash immediately if fan is failing
```

---

## Post-Crash Analysis

### 1. Kernel Dump Analysis

```bash
# Transfer vmcore to analysis machine
# Open with crash utility
crash /run/current-system/kernel /var/crash/<timestamp>.vmcore.zst

# Common crash commands
crash> bt          # Backtrace
crash> log         # Kernel log
crash> ps          # Process list
crash> vm          # Virtual memory info
```

### 2. Journal Analysis

```bash
# Compare crashed boot to baseline
journalctl -b -1 | grep -i "error\|fail\|warn\|crit"

# Check for thermal warnings
journalctl -b -1 | grep -i "thermal\|temp\|overheat"

# Check for fan issues
journalctl -b -1 | grep -i "fan\|cool"
```

### 3. Hardware Health Check

```bash
# Compare SMART data with previous snapshots
sudo smartctl -x /dev/nvme0 | grep -i "error\|fail\|warn"

# Check for media errors
sudo nvme smart-log /dev/nvme0
```

### 4. Version Tracking

Record versions for each crash:

```bash
# System version
nixos-version --json

# Kernel version
uname -r

# NVIDIA driver (if applicable)
modinfo nvidia | grep version
```

---

## Crash Pattern Recognition

### Likely Fan Failure

- Crashes on Fn+1 (max fan)
- Crashes in BIOS too
- Low temperatures at crash time
- One fan shows 0 or erratic RPM

### Likely Thermal Issue

- Crashes only under heavy load
- High temperatures before crash
- thermald logs show trip point activation
- Crash occurs after sustained high temp

### Likely Software Issue

- Crashes only in OS (not BIOS)
- Specific application triggers crash
- Kernel panic messages in journal
- Reproducible with specific workload

### Likely Hardware Issue (Other)

- Random crashes regardless of load
- Memory errors in dmesg
- SMART errors increasing
- Crashes during low-activity periods

---

## Escalation Path

If crashes persist after diagnostics:

1. **Document everything** - Logs, patterns, conditions
2. **Check System76 support** - Known issues for your model
3. **Hardware inspection** - Visual check for damage, dust, loose connections
4. **Component isolation** - Test with minimal peripherals
5. **Professional repair** - If hardware failure confirmed

---

## Related Documentation

- [system76-overview.md](system76-overview.md) - Hardware overview
- [system76-thermal-management.md](system76-thermal-management.md) - Thermal configuration
- [system76-fan-replacement.md](system76-fan-replacement.md) - Fan replacement guide
- [system76-firmware.md](system76-firmware.md) - Firmware information
