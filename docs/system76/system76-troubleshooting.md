# System76 Oryx Pro Troubleshooting

## Known Issues

### EC Temperature Over-Reporting

The System76 EC reports temperatures ~5C higher than actual, causing premature throttling.

**Solution:** Use thermald with `x86_pkg_temp` instead of system76-power.

### Fan Control Limitations

- EC has hard-coded fan curves (not adjustable)
- Software PWM writes are immediately overridden
- CoolerControl causes system instability - **keep disabled**
- Only manual control: Fn+1 for max speed

---

## Thermal Management

### Why thermald Instead of system76-power

| Aspect      | system76-power        | thermald                   |
| ----------- | --------------------- | -------------------------- |
| Temp Source | EC (over-reports ~5C) | x86_pkg_temp (accurate)    |
| Throttling  | EC-controlled         | RAPL, powerclamp, P-states |
| Config      | Hard-coded            | Customizable XML           |

### thermald Configuration

```nix
# modules/system76/services.nix
services.thermald = {
  enable = true;
  configFile = ./thermald.conf.xml;
};
```

Trip points in `thermald.conf.xml`:

| Temperature | Mode       | Action                                   |
| ----------- | ---------- | ---------------------------------------- |
| 85C         | Sequential | Apply cooling methods one at a time      |
| 92C         | Parallel   | Apply all cooling methods simultaneously |

### TCC Offset

Set to 0 to allow CPU full thermal headroom (thermald manages actual throttling):

```nix
systemd.tmpfiles.rules = [
  "w /sys/class/thermal/cooling_device13/cur_state - - - - 0"
];
```

### Monitoring

```bash
# Real-time temperatures
watch -n 1 sensors

# CPU package (accurate)
watch -n 1 'sensors coretemp-isa-0000 | grep Package'

# thermald logs
journalctl -u thermald -f

# Fan status
sensors system76-isa-0000 | grep fan
```

| Metric      | Normal    | Warning        |
| ----------- | --------- | -------------- |
| CPU Package | 40-85C    | >90C sustained |
| PCH         | 45-65C    | >80C           |
| Fan RPM     | 2000-4500 | 0 or erratic   |

---

## Crash Diagnostics

### Known Crash Causes

#### 1. Fan Failure Crash

**Symptoms:**

- Crash on Fn+1 (max fan speed)
- Crashes even in BIOS
- Low temperature at crash time
- Abrupt power off (no kernel panic)

**Cause:** Failed fan cannot achieve max RPM, EC triggers protective shutdown.

**Solution:** Replace dual-fan assembly. See [Fan Replacement](#fan-replacement) below.

**Workaround:** Avoid Fn+1, let thermald manage temps.

#### 2. CoolerControl Conflict

**Symptoms:** Crash when CoolerControl running + Fn+1 pressed.

**Cause:** CoolerControl and EC conflict over fan control.

**Solution:** `programs.coolercontrol.enable = false;`

#### 3. Thermal Shutdown (EC)

**Symptoms:** Shutdown during heavy load, EC shows higher temp than x86_pkg_temp.

**Cause:** EC over-reports temps, triggers premature shutdown.

**Solution:** Use thermald. See [Thermal Management](#thermal-management) above.

### Diagnostic Configuration

```nix
# Already configured in modules/system76/
boot.crashDump.enable = true;           # Crash kernel
boot.kernel.sysctl."kernel.sysrq" = 1;  # SysRq enabled
services.journald.storage = "persistent";  # Logs survive reboot
```

### SysRq Key Reference

With `kernel.sysrq = 1`, use `Alt+SysRq+<key>` for emergency actions:

| Key | Action                                         |
| --- | ---------------------------------------------- |
| `b` | Immediate reboot (no sync)                     |
| `o` | Power off                                      |
| `s` | Sync filesystems                               |
| `u` | Remount read-only                              |
| `e` | SIGTERM to all processes                       |
| `i` | SIGKILL to all processes                       |
| `c` | Trigger crash dump (if crashkernel configured) |

**Safe reboot sequence:** `Alt+SysRq` + `R E I S U B` (mnemonic: "Reboot Even If System Utterly Broken")

### When a Crash Occurs

1. **After reboot, collect logs:**

   ```bash
   mkdir -p ~/crash-logs
   sudo journalctl -b -1 -k > ~/crash-logs/kernel.log
   sudo journalctl -b -1 > ~/crash-logs/journal.log
   sensors > ~/crash-logs/sensors.txt
   ```

2. **Analyze:**

   ```bash
   journalctl -b -1 | grep -i "error\|fail\|thermal\|fan"
   ```

3. **Record context:** Time, workload, power state, Fn keys pressed, temperature.

### Crash Timeline Investigation

```bash
# 1. List all boots
sudo journalctl --list-boots

# 2. Get logs from crashed boot (-1 = previous boot)
sudo journalctl -b -1 --no-pager > ~/crash-logs/full-journal.log

# 3. Extract timeline of errors
sudo journalctl -b -1 -p err --no-pager > ~/crash-logs/errors-only.log

# 4. Check for thermal events
sudo journalctl -b -1 | grep -i "thermal\|temperature\|trip\|throttl" > ~/crash-logs/thermal.log

# 5. Check for hardware errors
sudo journalctl -b -1 | grep -i "hardware\|error\|fail\|mce\|pcie" > ~/crash-logs/hardware.log

# 6. Compare with successful boot
diff <(journalctl -b -1 -p err) <(journalctl -b 0 -p err)
```

### Crash Pattern Recognition

| Pattern                        | Likely Cause   |
| ------------------------------ | -------------- |
| Crash on Fn+1, even in BIOS    | Fan failure    |
| Crash under load, high temp    | Thermal issue  |
| Crash only in OS, specific app | Software issue |
| Random crash, low activity     | Hardware issue |

---

## Fan Replacement

### When to Replace

- System crashes on Fn+1
- Fan shows 0 RPM or erratic readings
- Grinding/clicking noise

### Diagnosis

```bash
# Monitor fans
watch -n 0.5 'sensors system76-isa-0000 | grep fan'

# Log before testing Fn+1 (WARNING: may crash)
while true; do
  echo "$(date +%H:%M:%S) CPU:$(cat /sys/class/hwmon/hwmon7/fan1_input) GPU:$(cat /sys/class/hwmon/hwmon7/fan2_input)"
  sleep 0.5
done | tee ~/fan_test.log
```

### Parts

**Complete assembly (required):** `6-31-P65S2-103` (~$70-80)

| Source                  | Price |
| ----------------------- | ----- |
| Linda Parts (cdrtd.com) | ~$70  |
| Amazon                  | ~$80  |

> **Important:** Fans cannot be replaced individually - entire dual-fan assembly must be replaced.

### Replacement Procedure

1. **Prepare:** Shut down, disconnect AC, ground yourself
2. **Disassemble:**
   - Remove bottom panel screws
   - Disconnect battery
   - Disconnect fan cables (pull straight up)
   - Remove heatsink screws (diagonal pattern)
   - Twist gently to break thermal paste seal
3. **Clean:** IPA on CPU/GPU dies, let dry
4. **Install:**
   - Pea-sized thermal paste on CPU and GPU dies
   - Position heatsink, align holes
   - Tighten screws diagonally
   - Connect fan cables
5. **Reassemble:** Battery, bottom panel, screws

### Verify

```bash
sensors system76-isa-0000
# Should show both fans with RPM readings
```

---

## Stress Testing

```bash
# CPU stress (monitor temps in another terminal)
stress-ng --cpu $(nproc) --timeout 10m

# Memory test
memtester 8192 1

# GPU stress
glmark2

# Combined (may trigger issues)
stress-ng --cpu 12 --vm 4 --vm-bytes 2G --timeout 10m
```

---

## Quick Reference

| Issue          | Check                    | Solution                            |
| -------------- | ------------------------ | ----------------------------------- |
| High temps     | `sensors`, thermald logs | Verify thermald running, check fans |
| Crash on Fn+1  | Fan RPM before crash     | Replace fan assembly                |
| Random crash   | `journalctl -b -1`       | Check logs for errors               |
| No fan control | Expected                 | EC controls fans, not software      |
