# System76 Crash Diagnostics Playbook

This guide documents the instrumentation now built into the `system76` host profile so recurring crashes leave actionable evidence. Follow it after the next rebuild to capture logs, kernel dumps, and hardware telemetry without bolting on ad hoc tooling.

---

## 1. Configuration Summary

- `modules/system76/boot.nix`: enables `boot.crashDump` with a 512 MiB reservation so a secondary kernel boots on panic, and raises kernel log verbosity plus `kernel.sysrq=1` for manual dumps.
- `modules/system76/services.nix`: forces `journald.storage = "persistent"` and turns on `systemd-coredump` so journals and user-space cores survive unexpected resets.
- `modules/system76/packages.nix`: includes `lm_sensors`, `smartmontools`, `nvme-cli`, `stress-ng`, `memtester`, `glmark2`, and `hwinfo` for on-device diagnostics.

Rebuild to apply:

```bash
nix build .#nixosConfigurations.system76.config.system.build.toplevel
./result/bin/switch-to-configuration test  # or switch per standard workflow
```

Reboot once so the crash kernel reservation and sysctls take effect.

---

## 2. Verifying the Instrumentation

After rebooting into the updated generation:

1. Confirm persistent journaling works:

   ```bash
   sudo journalctl --list-boots
   ```

   Expect multiple boot IDs without `(boot has been rotated)` warnings.

2. Ensure the crash kernel is reserved:

   ```bash
   cat /proc/cmdline | tr ' ' '\n' | grep crashkernel
   sudo journalctl -b | grep -F "loading crashdump kernel" -m1
   ```

3. Check that the capture environment is ready:

   ```bash
   sudo kdumpctl status  # should report "Ready to kdump"
   ```

4. Validate SysRq and logging defaults:
   ```bash
   sudo sysctl kernel.sysrq            # expect 1
   sudo sysctl kernel.printk           # expect "7 4 1 7"
   ```

---

## 3. When a Crash Occurs

1. If the system drops you into the crash kernel’s rescue shell, dump memory immediately:

   ```bash
   makedumpfile -c --message-level 1 --output /var/crash/$(date +%F-%H%M%S).vmcore.zst /proc/vmcore
   sync
   reboot -f
   ```

2. Once the host is back up, collect evidence from the prior boot:

   ```bash
   sudo journalctl -b -1 -k > logs/kernel-$(date +%F-%H%M%S).log
   sudo journalctl -b -1 > logs/journal-$(date +%F-%H%M%S).log
   ```

3. Capture hardware telemetry:

   ```bash
   sudo smartctl -x /dev/nvme0 > logs/smart-$(date +%F-%H%M%S).txt
   sudo nvme smart-log /dev/nvme0 >> logs/smart-$(date +%F-%H%M%S).txt
   sudo sensors > logs/sensors-$(date +%F-%H%M%S).txt
   ```

4. Record summary data points (time, workload, power state) alongside the logs for pattern analysis.

---

## 4. Stress and Reproduction Tests

Use the bundled tooling to provoke failures under controlled conditions:

- CPU / memory:
  ```bash
  stress-ng --cpu 16 --vm 4 --vm-bytes 2G --timeout 10m
  memtester 8192 1
  ```
- GPU:
  ```bash
  glmark2
  ```
- Full-system telemetry while testing:
  ```bash
  watch -n1 sensors
  nvidia-smi -l 1
  ```

Log every run (command, duration, outcome) so we can correlate which subsystem triggers the crash.

---

## 5. Post-Crash Analysis Checklist

1. **Kernel dump**: transfer `/var/crash/*.vmcore.zst` to an analysis machine and open with:
   ```bash
   crash /run/current-system/kernel /var/crash/<timestamp>.vmcore.zst
   ```
2. **Journals**: diff `journalctl -b -1` against baseline boots to spot new warnings.
3. **Hardware counters**: compare fresh `smartctl`/`nvme smart-log` output with prior snapshots for incrementing media or CRC errors.
4. **Regression tracking**: note the kernel, NVIDIA driver, and userland versions tied to each crash (available via `nixos-version --json` and `modinfo nvidia`).

Persist each investigation in `logs/` or your incident tracker so recurring faults have complete context for escalation.
