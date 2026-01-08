# System76 Oryx Pro Fan Replacement Guide

## Hardware Overview

| Property       | Value                                          |
| -------------- | ---------------------------------------------- |
| System76 Model | Oryx Pro (oryp4)                               |
| Clevo Chassis  | P950Ex                                         |
| Cooling Design | Unified dual-fan assembly with shared heatsink |

## Fan Configuration

This system uses a **unified dual-fan assembly** where both fans are mounted on a single metal bracket attached to a shared heatsink with copper heatpipes. The fans **cannot be replaced individually** - the entire dual-fan assembly must be replaced as a unit.

### Fan Identification

| Position     | Model Code | Full Part Number   | Specs      |
| ------------ | ---------- | ------------------ | ---------- |
| Bottom (CPU) | FGFG       | DFS541105FC0T-FGFG | DC 5V 0.5A |
| Top (GPU)    | FGFF       | DFS541105FC0T-FGFF | DC 5V 0.5A |

Both fans are manufactured by Forcecon and share the same base model `DFS541105FC0T`, differing only in the suffix which indicates position/connector orientation.

### Assembly Structure

```
┌─────────────────────────────────────┐
│  Heatsink (copper heatpipes + fins) │
├─────────────────────────────────────┤
│  ┌─────────┐  Copper   ┌─────────┐  │
│  │ GPU Fan │  Heatpipe │ CPU Fan │  │
│  │  FGFF   │◄─────────►│  FGFG   │  │
│  └─────────┘           └─────────┘  │
│      Metal bracket (unified)        │
└─────────────────────────────────────┘
```

## Replacement Parts

### Complete Assembly (Recommended)

**Part Number:** `6-31-P65S2-103`

This includes:

- Heatsink with copper heatpipes
- Both fans (FGFG + FGFF) as unified bracket
- Mounting hardware

| Source                  | Price | Link                                                                                                                                                                              |
| ----------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linda Parts (cdrtd.com) | ~$70  | [Product Page](https://www.cdrtd.com/products/laptop-cpu-gpu-fan-heatsink-for-clevo-p650rs-p650rs-g-6-31-p65s2-103-dfs541105fc0t-fgfg-dfs541105fc0t-fgff-dfs501105fr0t-fhcx.html) |
| Amazon.ca               | ~$80  | Search: 6-31-P65S2-103                                                                                                                                                            |
| Newegg                  | ~$365 | Overpriced - avoid                                                                                                                                                                |

### Alternative Part Numbers

| Part Number    | Description                   | Notes                       |
| -------------- | ----------------------------- | --------------------------- |
| 6-31-P65S2-103 | Complete heatsink + dual fans | **Recommended**             |
| 31-P65S2-102   | Heatsink module with fans     | Same assembly, alternate PN |

### Parts to AVOID

These part numbers are for different P650 variants and may not be compatible:

| Part Number        | Intended For      | Why Incompatible                 |
| ------------------ | ----------------- | -------------------------------- |
| 6-31-P6502-101     | P650SE/SA (oryp3) | Different fan base model         |
| 6-31-P650N-201     | P650N/P670        | Different heatsink design        |
| DFS501105FR0T-FHCX | Various P650      | Different fan model (501 vs 541) |

## Required Materials

- Replacement dual-fan assembly (6-31-P65S2-103)
- Thermal paste (Arctic MX-4 or equivalent)
- Isopropyl alcohol (90%+ for cleaning)
- Small Phillips screwdriver
- Plastic spudger (for cable disconnection)
- Anti-static precautions

## Replacement Procedure

### Preparation

1. Shut down the system completely
2. Disconnect AC power
3. Ground yourself (anti-static strap recommended)

### Disassembly

1. **Remove bottom panel**
   - Remove all Phillips screws from bottom cover
   - Carefully pry off bottom panel starting from rear corners

2. **Disconnect battery** (if accessible)
   - Locate battery connector on motherboard
   - Carefully disconnect to prevent shorts

3. **Disconnect fan cables**
   - Locate fan connectors on motherboard (typically near heatsink)
   - Gently pull connectors straight up - do not pull by wires

4. **Remove heatsink assembly**
   - Remove heatsink mounting screws in diagonal/alternating pattern
   - Note: Screws may be numbered (follow 1-2-3-4 pattern if marked)
   - Gently twist heatsink to break thermal paste seal
   - Lift assembly straight up

### Cleaning

1. Use isopropyl alcohol to clean old thermal paste from:
   - CPU die
   - GPU die
   - Any VRM contact points

2. Allow surfaces to dry completely

### Installation

1. **Apply thermal paste**
   - Small dot (pea-sized) on CPU die center
   - Small dot on GPU die center
   - Do not spread - mounting pressure will distribute

2. **Position new heatsink assembly**
   - Align mounting holes
   - Ensure heatpipes contact CPU and GPU dies

3. **Secure heatsink screws**
   - Tighten in diagonal pattern
   - Do not overtighten - snug is sufficient

4. **Connect fan cables**
   - Ensure proper connector orientation
   - Push connectors firmly until seated

5. **Reassemble**
   - Reconnect battery
   - Replace bottom panel
   - Install all screws

### Post-Installation Verification

```bash
# Check fan detection
sensors system76-isa-0000

# Expected output should show both fans with RPM readings:
# CPU fan:         XXXX RPM
# GPU fan:         XXXX RPM

# Monitor during stress test
watch -n 1 'sensors system76-isa-0000'
```

## Diagnosing Fan Failure

### Symptoms of Fan Failure

| Symptom                         | Likely Cause                      |
| ------------------------------- | --------------------------------- |
| System crash when pressing Fn+1 | One fan cannot achieve max RPM    |
| Fan shows 0 RPM in sensors      | Fan motor failure or disconnected |
| Grinding/clicking noise         | Bearing failure                   |
| Erratic RPM readings            | Motor or tachometer failure       |

### Diagnostic Commands

```bash
# Quick fan check
sensors | grep -A3 "system76-isa"

# Continuous monitoring
watch -n 0.5 'cat /sys/class/hwmon/hwmon7/fan1_input /sys/class/hwmon/hwmon7/fan2_input'

# Check PWM values
cat /sys/class/hwmon/hwmon7/pwm1
cat /sys/class/hwmon/hwmon7/pwm2
```

### Fan Failure Test (CAUTION: May crash system)

If you suspect a fan failure:

1. Start logging:

   ```bash
   while true; do
     echo "$(date +%H:%M:%S) CPU:$(cat /sys/class/hwmon/hwmon7/fan1_input) GPU:$(cat /sys/class/hwmon/hwmon7/fan2_input)" >> ~/fan_log.txt
     sleep 0.5
   done
   ```

2. Press Fn+1 to trigger max fan speed

3. If system crashes, check `~/fan_log.txt` after reboot - the fan showing lower/erratic RPM before crash is likely the failed unit

**Warning:** This test may crash your system if a fan is failing.

## Related Documentation

- [system76-overview.md](system76-overview.md) - Hardware overview
- [system76-thermal-management.md](system76-thermal-management.md) - Thermal configuration
- [system76-crash-diagnostics.md](system76-crash-diagnostics.md) - Crash analysis
