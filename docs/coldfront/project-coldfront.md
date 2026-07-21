# Project Coldfront

Host: `coldfront`.

High-end Intel Arrow Lake workstation, productivity first (compilation, local
LLM work) and gaming second. Functional, not pretty, no RGB. This revision
reflects the final purchased build as validated on 2026-07-20 and supersedes
the earlier Thermaltake CTE C750 / Gigabyte 5080 / ARCTIC 420 plan in full.

Source of truth for hardware research is the
[Bad3r/project-coldfront](https://github.com/Bad3r/project-coldfront)
repository (`pc-build.md`, `build-report.md`, `assembly-checklist.md`, with
verbatim source copies under `sources/`). This document carries the facts
needed to plan, assemble, and operate the host; the OS plan lives in
[nixos-setup.md](nixos-setup.md).

## Parts List

| Part          | Product                                          | Model number           |
| ------------- | ------------------------------------------------ | ---------------------- |
| CPU           | Intel Core Ultra 9 285K (Arrow Lake-S)           | BX80768285K            |
| Motherboard   | ASUS ROG Maximus Z890 Hero (ATX)                 | 90MB1IX0-M0EAY0        |
| GPU           | ASUS GeForce RTX 5080 Noctua OC Edition 16G      | RTX5080-O16G-NOCTUA    |
| RAM           | Corsair Vengeance DDR5 CUDIMM 48GB (2x24GB) 8400 | CMKC48GX5M2X8400C40    |
| SSD           | WD_BLACK SN8100 4TB PCIe 5.0 NVMe M.2            | WDS400T1X0M-00CMT0     |
| PSU           | ASUS ROG Strix 1200W Platinum                    | ROG-STRIX-1200P-GAMING |
| CPU cooler    | Cooler Master MasterLiquid 360 Atmos (Black)     | MLX-D36M-A25PZ-R1      |
| Contact frame | Thermalright LGA1851-BCF Black (V2)              | TR-L18517BCFV2-BK      |
| Case          | Antec Flux SE (Mid Tower)                        | UPC 0-761345-10177-6   |
| Case fans     | ARCTIC P14 Pro PST 140 mm (1x 5-pack, 5 fans)    | ACFAN00319A            |
| Fan hub       | ARCTIC Case Fan Hub (10-port PWM, SATA)          | ACFAN00175A            |
| Thermal paste | Noctua NT-H2 (3.5g, AM5 Edition)                 | NT-H2 3.5g AM5         |

Procurement state (2026-07-20): everything is purchased. All parts gating
assembly are on hand. The SN8100 is ordered but not yet shipped and gates only
OS installation. The P14 Pro 5-pack and the ARCTIC hub arrive 27-31 July,
after assembly day, and gate only the deferred Phase 8 fan swap; the build
completes on the case's five stock fans first.

## Storage Inventory

Beyond the new SN8100, coldfront receives both storage devices currently in
the `system76` host. system76 itself keeps running on replacement drives.

| Disk | Device                                           | Bus                  | Role on coldfront                         |
| ---- | ------------------------------------------------ | -------------------- | ----------------------------------------- |
| A    | WD_BLACK SN8100 4TB (new)                        | M.2_1, CPU PCIe 5.0  | NixOS (LUKS2), daily driver               |
| B    | 2TB NVMe (ex system76 root drive)                | M.2_2, CPU PCIe 4.0  | Windows 11 (BitLocker), gaming            |
| S    | Samsung 850 Pro 4TB SATA SSD (ex system76 /data) | SATA 6 Gb/s, chipset | Shared BitLocker NTFS drive for both OSes |

Disk B's exact model is recorded when it is pulled from system76; both moved
drives predate this build. B in M.2_2 uses CPU Gen4 lanes and does not touch
GPU lanes. S (2.5 in, 3D V-NAND MLC) caps at SATA speeds (about 550 MB/s),
which is adequate for a bulk game library and shared data; latency-sensitive
titles install on B.

Slot rule: M.2_3 and M.2_4 stay empty permanently. Populating either drops
the GPU slot from PCIe 5.0 x16 to x8.

## Component Specifications

### CPU: Intel Core Ultra 9 285K

- Socket FCLGA1851, Arrow Lake-S, compute tile on TSMC N3B.
- 24 cores / 24 threads: 8 Performance (Lion Cove) + 16 Efficient (Skymont),
  no Hyper-Threading.
- P-core 3.7 GHz base, up to 5.7 GHz (Thermal Velocity Boost); E-core 3.2 to
  4.6 GHz. 36 MB L3, 40 MB L2.
- Power: PL1 125 W, PL2 250 W; measures about 245 W sustained all-core.
- Memory: native DDR5-6400 CUDIMM at 1 DIMM per channel (DDR5-5600 UDIMM).
  Dual channel, max 256 GB, ECC supported by the CPU (kit is non-ECC).
- PCIe: 24 CPU lanes, 20x PCIe 5.0 (16 GPU + 4 for one M.2) plus 4x PCIe 4.0
  (one M.2). Chipset link DMI 4.0 x8.
- Integrated Xe-LPG graphics (4 Xe-cores, up to 2.0 GHz): used for GPU-less
  bring-up over the board HDMI port, available for VA-API decode later.
- Ships without a cooler.

### Motherboard: ASUS ROG Maximus Z890 Hero

- LGA1851, Intel Z890, ATX (30.5 x 24.4 cm). Native Core Ultra Series 2
  support. Latest BIOS as of 2026-07-19: 3202 (2026-05-08).
- Memory: 4x DIMM, up to DDR5-9200+ (OC) with CUDIMM support. The build's
  exact kit (Ver 5.53.13) is on the ASUS QVL at 8400 MT/s in 1- and 2-DIMM
  population, not 4.
- 6x M.2: M.2_1 CPU PCIe 5.0 x4 (dedicated, has board heatsink); M.2_2 CPU
  PCIe 4.0 x4; M.2_3 / M.2_4 CPU PCIe 5.0 x4 shared with the GPU slot (ASUS:
  "When M.2_3 or M.2_4 is enabled, PCIEX16(G5) will run x8 only."); M.2_5 /
  M.2_6 chipset PCIe 4.0 x4. 4x SATA 6 Gb/s ports (chipset).
- PCIe slots: 1x PCIe 5.0 x16 (CPU) with Q-Release Slim, 1x PCIe 4.0 x16
  length at x4 (chipset), 1x PCIe 4.0 x1.
- Networking: 1x Intel 2.5 GbE + 1x Realtek 5 GbE, Wi-Fi 7 (2x2, 802.11be,
  module vendor not published by ASUS), Bluetooth 5.4.
- Rear I/O: 2x Thunderbolt 4 (USB4, DP out), 1x HDMI 2.1 (iGPU path for
  GPU-less bring-up), about 11 USB ports total.
- USB BIOS FlashBack works on standby power with no CPU installed (BIOS file
  renamed to `A5555.CAP`; port is the lower red USB 10Gbps Type-A).
- Fan headers: CPU_FAN, CPU_OPT, CHA_FAN1-4, AIO_PUMP at 1 A / 12 W each;
  W_PUMP+ at 3 A / 36 W. AIO_PUMP and W_PUMP+ default to full speed.
- VRM: 22+1+2+2 teamed power stages, 110 A main stages.

### GPU: ASUS RTX 5080 Noctua OC Edition (RTX5080-O16G-NOCTUA)

- Blackwell GB203, 10,752 CUDA cores, PCIe 5.0 x16.
- 16 GB GDDR7, 256-bit, 30 Gbps, 960 GB/s.
- Clocks: 2295 MHz base; boost 2700 MHz (Default) / 2730 MHz (OC Mode via GPU
  Tweak III). Measured about 2792 MHz average across 25 games (TechPowerUp).
- Power: 360 W default TGP, board power limit adjustable -31% to +25% (max
  450 W). 1x 16-pin 12V-2x6 (600 W rated) in a recessed top-edge cutout at
  mid-card. Dual BIOS switch (P/Q), the two BIOSes differ only in fan curve.
- Outputs: 3x DisplayPort 2.1b UHBR20 + 2x HDMI 2.1b (max 4 displays).
- Cooler: 3x Noctua NF-A12x25 G2 120 mm fans on a 4-slot vapor-chamber
  heatsink; fans stop below 55 C (0 dB idle). Open-bench reference: 64 C GPU,
  72 C memory at 23.9 dBA (Quiet BIOS).
- Dimensions 385 x 151 x 80 mm (TPU measured 390 mm, 2667 g). About 2.7 kg;
  a matching anti-sag holder is bundled and used (the case has none).

### RAM: Corsair Vengeance DDR5 CUDIMM 48GB (CMKC48GX5M2X8400C40)

- 2x 24 GB, single-sided, SK Hynix DRAM, 35 mm tall.
- XMP: 8400 MT/s, 40-52-52-135, 1.40 V. JEDEC fallback 4800 MT/s at 1.10 V;
  the kit boots at 4800 until XMP is enabled.
- CUDIMM: an on-module clock driver (CKD) regenerates the memory clock;
  active on Intel 800-series boards only.
- DDR5-8400 remains an XMP overclock above the CPU's native 6400. QVL
  validation on this exact board raises confidence, not a guarantee.
  Fallback ladder: 8000, 7600, 6400.
- Capacity path: a second identical kit (4 DIMMs) drops speed to roughly the
  native 6400 class and leaves the QVL; a 2x 48 GB kit keeps 1DPC at speed.

### SSD (disk A): WD_BLACK SN8100 4TB (WDS400T1X0M-00CMT0)

- PCIe 5.0 x4, NVMe 2.0, M.2 2280, single-sided.
- Silicon Motion SM2508-class controller (SanDisk-relabeled), Kioxia/SanDisk
  BiCS8 218-layer TLC, DDR4 DRAM cache.
- Up to 14,900 / 14,000 MB/s sequential read/write, 2.3M / 2.4M IOPS (4TB).
- Power: 6.5 W average active read, 7.0 W active write, 5 mW sleep (PS4).
- Endurance 2,400 TBW; 5-year limited warranty.
- Bare SKU (no heatsink): it must sit under the Z890 Hero's M.2_1 heatsink.
  Firmware throttle point is 100 C; under a board heatsink it holds sustained
  writes without throttling.

### PSU: ASUS ROG Strix 1200W Platinum (ROG-STRIX-1200P-GAMING)

- 1200 W, ATX 3.1, PCIe Gen 5.1 ready. 80 PLUS Platinum, Cybenetics Platinum,
  Lambda A noise rating. +12V single rail 100 A.
- Native 16-pin connector on both PSU and component side; the bundled 750 mm
  16-pin-to-16-pin cable (600 W) feeds the GPU directly. Other connectors:
  24-pin, 2x EPS 4+4, 4x PCIe 6+2, 6x SATA, 3x peripheral.
- Fully modular, 135 mm dual-ball-bearing fan, 0 dB fan-stop mode with a
  physical button. 160 mm depth, 10-year warranty.
- Use only this unit's own modular cables. Modular pin-outs differ between
  PSU brands and models; a leftover cable from another unit can damage
  drives.

### CPU Cooler: Cooler Master MasterLiquid 360 Atmos + Thermalright Contact Frame

- 360 mm AIO: radiator 394 x 119 x 27.2 mm; installed stack with fans
  52.2 mm; 400 mm tubes; dual-chamber PWM pump (3.84 W, 0.32 A).
- Fans: 3x SickleFlow 120 Edge (690-2500 RPM, 0.2 A each, ARGB) joined by the
  bundled PWM splitter. No software, USB, or SATA dependency: pump and fans
  run from plain PWM headers (deliberate selection criterion; the optional
  MasterPlus software is Windows-only and unnecessary).
- LGA1851 mounting uses the LGA1700 hole pattern (identical locations per
  Intel). Thermal capability verified beyond 350 W real CPU power, well over
  the 285K's 245-250 W sustained.
- Contact frame: Thermalright LGA1851-BCF V2 replaces the socket's stock ILM
  to load the package evenly; expected effect single-digit degrees. The
  frame occupies only the ILM position; the cooler's four mounting holes stay
  free. Removing the stock ILM may void the board warranty; stock parts are
  bagged for reversal. Installation is the build's highest-care step.
- Paste: NT-H2 (center dot plus four corner dots). The AM5-shaped paste guard
  stays unused on LGA1851; the Atmos's bundled CryoFuze stays boxed as spare.

### Case: Antec Flux SE

- Mid tower, F-LUX airflow platform: recessed front fan channel behind mesh,
  PSU shroud with upward intake aimed at the GPU. 484 x 239 x 502 mm, 8.8 kg,
  7 expansion slots. Mini-ITX to E-ATX (up to 330 mm).
- Published clearances: GPU up to 408 mm (front fans live in the recessed
  channel, outside the main chamber), CPU cooler 180 mm, PSU 235 mm.
- Radiator support: front up to 420 mm, top up to 360 mm (drop-in bracket,
  60 mm stack budget), rear single 120/140 fan only.
- Included fans (all 4-pin PWM, no ARGB): 3x P12 front, 1x P12R reverse-blade
  on the PSU shroud (blows up at the GPU), 1x P14 rear. A built-in 5-port PWM
  hub (SATA powered, one uplink) ships pre-wired to all five.
- Storage: 2x 3.5"/2.5" cage in the basement + 1x 2.5" sled behind the tray
  (takes disk S). Front I/O: 2x USB 3.0, 1x USB-C 10 Gbps, combo audio.

## Clearances and Fitment (verified)

| #   | Check                       | Numbers                                              | Verdict                     |
| --- | --------------------------- | ---------------------------------------------------- | --------------------------- |
| 1   | GPU length, front fans only | case limit 408 mm; card 385 (390 measured)           | PASS, +23 mm (+18 measured) |
| 2   | GPU length, any front rad   | 408 - ~30 (radiator body intrusion) = ~378 < 385     | FAIL; top is the only spot  |
| 3   | Atmos 360 on top rails      | 394 mm radiator, 360-class mount                     | PASS by case spec           |
| 4   | Atmos top stack             | 27.2 + 25 = 52.2 mm vs 60 mm budget                  | PASS, 7.8 mm margin         |
| 5   | Contact frame vs cooler     | frame in ILM position; cooler uses the 4 board holes | PASS, no interaction        |
| 6   | PSU bay                     | 160 mm unit vs 235 mm incl. cables                   | PASS                        |
| 7   | 12V-2x6 side clearance      | >= 29 mm above card spine + recess; 35 mm straight   | PASS with routing care      |
| 8   | GPU thickness               | 4 slots (80-82 mm) in slots 1-4 of 7                 | PASS                        |
| 9   | Fan and pump currents       | pump 0.32 A / 1 A; 3 fans 0.6 A / 1 A; hub 1.4/4.5 A | PASS                        |

The front-radiator failure (check 2) is why the CPU radiator mounts on top as
exhaust: Antec's own flyer marks about 30 mm of main-chamber intrusion for a
front radiator body, and the 385 mm card needs more than the roughly 378 mm
that leaves.

## Cooling Configuration and Fan Plan

Airflow: front intake through the recessed channel, PSU-shroud fans feeding
the GPU from below, top (CPU radiator) and rear as exhaust. The GPU keeps the
entire front intake to itself.

Final layout (after the Phase 8 fan swap):

| Location          | Fan                          | Direction      |
| ----------------- | ---------------------------- | -------------- |
| Top               | Atmos 360, 3x SickleFlow 120 | Exhaust        |
| Front             | 3x P14 Pro 140               | Intake         |
| Rear              | 1x P14 Pro 140               | Exhaust        |
| PSU shroud pos. 1 | stock P12R reverse 120       | Intake, upward |
| PSU shroud pos. 2 | stock P12 120, face-down     | Intake, upward |

Assembly-day layout: the five stock fans as shipped (front 3x P12, rear P14,
shroud P12R) on the case's built-in hub; complete and safe for daily use.

Control: pump on AIO_PUMP (full speed), the three radiator fans on CPU_FAN
via the bundled splitter, case fans on CHA_FAN1 (built-in hub now, ARCTIC
10-port hub after Phase 8), the two shroud fans on CHA_FAN2 after Phase 8.
All fan control is BIOS Q-Fan; no OS-side fan software exists or is needed.
Gentle shared curve: about 600-900 RPM idle, 1200-1400 RPM under load.

## Power Budget

| Rail                   | Draw                                         |
| ---------------------- | -------------------------------------------- |
| CPU (PL2)              | up to 250 W (about 245 W measured sustained) |
| GPU (default TGP)      | 360 W; up to 450 W with the slider maxed     |
| Board, RAM, SSDs, fans | about 80 to 100 W                            |
| Sustained system peak  | about 690 to 710 W (800 W worst case)        |
| PSU capacity           | 1200 W                                       |
| Headroom               | about 490 W at defaults                      |

## Build Caveats

1. Contact frame install: board flat, fingers off exposed socket pins, all
   four screws started by hand, tightened gradually in a cross pattern (stock
   frame screws are Torx T20). May void the board warranty; stock parts kept.
2. DDR5-8400 is an XMP overclock; ladder down 8000 / 7600 / 6400 on
   instability. Four DIMMs forfeit 8400.
3. Disk A must sit under the board's M.2_1 heatsink or it throttles.
4. M.2_3 and M.2_4 stay empty (GPU x8 drop). B goes in M.2_2 only.
5. 12V-2x6: native PSU cable only, click-seat with no shoulder gap, 35 mm
   straight before the first bend, no side-panel pressure, re-check seating
   after the first heavy GPU session.
6. P14 Pro screw holes are tight: pre-run every screw on a flat surface
   before mounting fans in the case.
7. Q-Release Slim: to remove the GPU, hold the end nearest the rear I/O and
   lift slightly at an angle; do not force the card straight out.
8. Install the GPU's bundled anti-sag holder (2.7 kg card, no case support).
9. SATA power for disk S comes from this PSU's own modular SATA cables only
   (pin-out warning above).

## Sources

Full validation with verbatim source copies in
[Bad3r/project-coldfront](https://github.com/Bad3r/project-coldfront):
[sources/README.md](https://github.com/Bad3r/project-coldfront/blob/main/sources/README.md)
(index), cited throughout
[pc-build.md](https://github.com/Bad3r/project-coldfront/blob/main/pc-build.md)
and
[build-report.md](https://github.com/Bad3r/project-coldfront/blob/main/build-report.md).
Assembly procedure:
[assembly-checklist.md](https://github.com/Bad3r/project-coldfront/blob/main/assembly-checklist.md)
(Phases 0-8 with validation log).
