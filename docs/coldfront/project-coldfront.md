# Project Coldfront

Host: `coldfront`.

High-end Intel Arrow Lake workstation build. Functional, not pretty, no RGB.
All specifications below were validated against manufacturer product pages and independent reviews in 2026 (see Sources).
Every listed component is current and the parts are fully compatible with each other.

## Parts List

| Part          | Product                                          | Model number           |
| ------------- | ------------------------------------------------ | ---------------------- |
| CPU           | Intel Core Ultra 9 285K (Arrow Lake-S)           | BX80768285K            |
| Motherboard   | ASUS ROG Maximus Z890 Hero (ATX)                 | 90MB1IX0-M0EAY0        |
| GPU           | Gigabyte GeForce RTX 5080 Gaming OC 16G          | GV-N5080GAMING OC-16GD |
| RAM           | Corsair Vengeance DDR5 CUDIMM 48GB (2x24GB) 8400 | CMKC48GX5M2X8400C40    |
| SSD           | Crucial T710 4TB PCIe 5.0 NVMe M.2 (no heatsink) | CT4000T710SSD8-01      |
| PSU           | ASUS ROG Strix 1200W Platinum                    | ROG-STRIX-1200P-GAMING |
| AIO cooler    | ARCTIC Liquid Freezer III Pro 420                | ACFRE00181A            |
| Case          | Thermaltake CTE C750 Air (Full Tower)            | CA-1X6-00F1WN-00       |
| Case fans     | ARCTIC P14 Pro PST 140 mm (2x 5-pack, 10 fans)   | ACFAN00319A            |
| Fan hub       | ARCTIC Case Fan Hub (10-port PWM, SATA)          | ACFAN00175A            |
| Thermal paste | Noctua NT-H2 (3.5g, AM5 Edition)                 | NT-H2 3.5g AM5         |

## Component Specifications

### CPU: Intel Core Ultra 9 285K

- Socket LGA1851, Arrow Lake-S, built on TSMC N3B.
- 24 cores / 24 threads. 8 Performance cores (Lion Cove) + 16 Efficient cores
  (Skymont). No Hyper-Threading, so this i9-class part is 24T, down from the
  14900K's 32T.
- P-core 3.7 GHz base, 5.6 GHz boost, 5.7 GHz single-core max (Thermal Velocity
  Boost). E-core 3.2 GHz base, 4.6 GHz boost.
- 36 MB L3, 40 MB L2.
- Base power (PL1) 125 W, max turbo power (PL2) 250 W. Peaks around 250 to 260 W,
  loads near 80 to 82 C on strong cooling. Runs roughly 100 W lower on average
  than the i9-14900K. Gaming is a few percent behind the 14900K; productivity is
  about on par.
- Integrated Xe-LPG graphics (4 Xe-cores, up to 2.0 GHz) for display and media
  only. Not a gaming GPU.
- Native memory: DDR5-6400 (CUDIMM) or DDR5-5600 (UDIMM) at 1 DIMM per channel.
- 24 CPU PCIe lanes: 20x PCIe 5.0 (16 for the GPU + 4 for one M.2) plus 4x
  PCIe 4.0 (one M.2). Chipset link is DMI 4.0 x8.
- Ships without a cooler (K-series). An AIO or high-end air cooler is required.

### Motherboard: ASUS ROG Maximus Z890 Hero

- LGA1851, Intel Z890 chipset, ATX form factor (30.5 x 24.4 cm). Supports Intel
  Core Ultra Series 2 (Arrow Lake). Confirmed compatible with the 285K.
- Memory: 4x DDR5 DIMM, up to 256 GB, advertised up to DDR5-9200+ (overclock)
  with CUDIMM support, NitroPath DRAM, and AEMP III. Any rating above DDR5-6400
  is an XMP/OC figure, not the CPU's native speed.
- Top memory speeds require 1 DIMM per channel (2 DIMMs total). Populating all 4
  slots (2 DIMMs per channel) sharply reduces attainable speed.
- 6x M.2 slots:
  - M.2_1: CPU, PCIe 5.0 x4 (dedicated, does not share GPU lanes)
  - M.2_2: CPU, PCIe 4.0 x4
  - M.2_3: CPU, PCIe 5.0 x4 (shares lanes with the primary x16 slot)
  - M.2_4: CPU, PCIe 5.0 x4 (shares lanes with the primary x16 slot)
  - M.2_5: chipset, PCIe 4.0 x4
  - M.2_6: chipset, PCIe 4.0 x4
  - Net: 3x Gen5 + 3x Gen4; 4 CPU-attached + 2 chipset-attached.
- Enabling M.2_3 or M.2_4 drops the primary PCIe 5.0 x16 slot to x8.
- PCIe slots: 1x PCIe 5.0 x16 (CPU), 1x PCIe 4.0 x16-length running x4 (chipset,
  intended for the Thunderbolt card), 1x PCIe 4.0 x1.
- Networking: Realtek 5 GbE + Intel 2.5 GbE (two different vendors). Wi-Fi 7
  (2x2, 802.11be) + Bluetooth 5.4.
- 2x Thunderbolt 4 (USB-C, 40 Gbps, USB4-compliant). These same two USB-C ports
  are the USB4 implementation, not separate additional ports. About 11 rear USB
  ports total.
- VRM: 22+1+2+2 teamed power stages, main CPU stages rated 110 A.

### GPU: Gigabyte RTX 5080 Gaming OC 16G

- Blackwell GB203, 10,752 CUDA cores.
- 16 GB GDDR7, 256-bit bus, 30 Gbps, 960 GB/s bandwidth.
- Boost clock 2730 MHz in the card's default OC mode (a factory overclock over
  the 2617 MHz reference boost). Base clock is about 2295 MHz. The 2730 MHz
  figure Gigabyte prints as "Core Clock" is the boost, not the base.
- Bus interface PCIe 5.0 x16.
- Total graphics power (TGP) 360 W. NVIDIA and Gigabyte both recommend an 850 W
  PSU minimum.
- 1x 16-pin 12V-2x6 (12VHPWR) power connector. A 12V-2x6 to 3x PCIe 8-pin adapter
  is bundled but is not needed with this PSU (see PSU below).
- Outputs: 3x DisplayPort 2.1b + 1x HDMI 2.1b. Up to 7680x4320.
- Dimensions 340 x 140 x 70 mm, about 3.5 slots thick, roughly 1.8 kg.

### RAM: Corsair Vengeance DDR5 CUDIMM 48GB (CMKC48GX5M2X8400C40)

- 48 GB kit, 2x 24 GB, single-rank. DDR5-8400 (8400 MT/s; the actual clock is
  4200 MHz, "MHz" on the label is the standard MT/s marketing convention).
- CL40-52-52-135 at XMP, 1.40 V. JEDEC/SPD fallback is CL40-40-40-77 at 1.1 V.
- CUDIMM (Clocked Unbuffered DIMM): an onboard Client Clock Driver (CKD) chip
  regenerates the host clock to restore signal integrity, which is what makes
  reliable DDR5-6400+ possible. The CKD runs in active mode only on Intel Arrow
  Lake (Core Ultra 200S) with a Z890 board. On any other platform (including
  AMD AM5) the module falls back to bypass mode and is capped near DDR5-6000.
- DDR5-8400 is an XMP overclock above the CPU's native DDR5-6400. Reaching it
  needs 1 DIMM per channel (this 2-DIMM kit), Gear 2, a current BIOS, and a
  capable memory controller. It is achievable on this board/CPU but not
  guaranteed plug-and-play.
- Without XMP (stock BIOS defaults), the kit boots at its JEDEC SPD base of
  DDR5-4800, the CL40-40-40-77 at 1.1 V profile above. It does not auto-run the
  native 6400; enable the XMP profile to target 8400.
- Capacity upgrade path (speed vs cost tradeoff):
  - Cheaper, keeps the current kit: add a second identical 2x24 GB kit (same
    CMKC48GX5M2X8400C40) for 96 GB. Four sticks is 2 DIMMs per channel
    (dual-rank), so the 8400 XMP will not train; expect roughly DDR5-6000 to
    6800 (often near 6400) and plan to set speed and timings manually. Use the
    same model; do not mix in a different-spec kit.
  - Fastest, replaces the kit: swap to a 2x48 GB (96 GB) kit and stay at 2 DIMMs
    (1 per channel) to keep 8000+. 48 GB DIMMs are dual-rank, so the top bins are
    a little harder than the current 2x24.
    Gaming does not use more than 48 GB, so more capacity mainly helps heavy
    creator or workstation work, which often values 96 GB over the bandwidth given
    up at ~6400.
- Height 35 mm (standard Vengeance heatspreader, not low-profile). No clearance
  concern with the AIO.

### SSD: Crucial T710 4TB (CT4000T710SSD8-01)

- PCIe 5.0 (Gen5) x4, NVMe 2.0, M.2 2280 single-sided.
- Sequential up to 14,500 / 13,800 MB/s (read/write) on the 4TB model. Up to
  2.2M / 2.3M IOPS. Note: the 14,900 MB/s read figure on Crucial's page applies
  only to the 1TB SKU; 14,500 is correct for this 4TB drive.
- Silicon Motion SM2508 controller (TSMC 6 nm), Micron G9 276-layer 3D TLC NAND,
  about 4 GB LPDDR4 DRAM cache. More power-efficient than the previous T705
  (Phison E26): about 8.25 W vs 11.25 W.
- 2,400 TBW endurance, 5-year warranty (or TBW limit, whichever comes first).
- This "-01" part is the no-heatsink variant. Per Crucial, a non-heatsink T710
  must be installed with a motherboard or third-party M.2 heatsink for full
  performance. The heatsink model is a separate part, CT4000T710SSD5.

### PSU: ASUS ROG Strix 1200W Platinum (ROG-STRIX-1200P-GAMING)

- 1200 W. 80 PLUS Platinum and Cybenetics Platinum. ("1200P" is the model code,
  the P denotes Platinum.)
- ATX 3.1, PCIe 5.1 ready.
- 1x native 12V-2x6 connector rated 600 W (native 16-pin to 16-pin cable
  included). Powers the RTX 5080 directly; the GPU's 8-pin adapter is not needed.
- Fully modular. 135 mm dual-ball-bearing fan with a 0 dB idle mode.
- 160 mm depth. 10-year warranty.

### AIO Cooler: ARCTIC Liquid Freezer III Pro 420

- 420 mm radiator (3x 140 mm fans). Radiator 458 x 138 x 38 mm. Case-side
  clearance needed 65 mm (38 mm radiator + 27 mm P14 Pro fans).
- 3x P14 Pro fans (7-blade, 140 mm, 400 to 2500 RPM PWM). VRM fan on the pump.
  PWM pump 800 to 2800 RPM. 500 mm tubes.
- Sockets: Intel LGA1851 and LGA1700; AMD AM5 and AM4. The LGA1851 contact frame
  (offset mount tuned to the CPU hotspot) and MX-6 paste are included in the box.
- 6-year warranty.
- The "Pro" model differs from the standard Liquid Freezer III by its 7-blade
  P14 Pro fans, higher radiator fin density, and optimized Intel offset mount. It
  is not a thicker radiator: both the Pro and the standard use a 38 mm radiator.
- Comfortably rated for the 285K's 250 W+ heat load.

### Case: Thermaltake CTE C750 Air

- Full tower with Centralized Thermal Efficiency (CTE) layout: the motherboard
  tray is rotated 90 degrees so the rear I/O and GPU outputs face upward. The CPU
  ends up near the front intake and the GPU near the rear, giving each its own
  cold-air path.
- Supports Mini-ITX, Micro-ATX, ATX, and E-ATX (up to 12 x 13 in).
- Dimensions 565.2 x 327 x 599.2 mm (H x W x D). Weight 16.7 kg. 7 expansion
  slots.
- 3x CT140 fans pre-installed (140 mm, about 1500 RPM, 30.5 dBA), at front, top,
  and rear.
- Max GPU length: 420 mm with no radiator in the GPU path, 370 mm with a
  radiator in the GPU path.
- Max CPU air cooler height: 190 mm.
- PSU: ATX (PS2), up to 200 mm long.
- Drive bays: 7x 3.5 in or 12x 2.5 in.
- 4 mm tempered glass left side panel, mesh front panel (the "Air" model).
- Includes a rotatable PCI-E / riser mounting bracket that accepts 90 or 180
  degree riser cables for optional vertical GPU mounting. The riser cable itself
  is not included in the box.

## Compatibility Verification

| Pairing                                           | Result                                     |
| ------------------------------------------------- | ------------------------------------------ |
| CPU (LGA1851) to Motherboard (Z890, LGA1851)      | OK. Native support.                        |
| AIO (LGA1851 contact frame in box) to CPU         | OK. Rated for 250 W+.                      |
| AIO (420 mm, 38 mm) to Case                       | OK. Fits front, motherboard side, or rear. |
| RAM (CUDIMM DDR5-8400) to CPU + Board             | OK on Z890 at 1DPC. 8400 is an XMP OC.     |
| GPU (PCIe 5.0 x16, 340 mm) to Board + Case        | OK. Board x16 slot; case fits 340 mm.      |
| GPU 12V-2x6 to PSU native 12V-2x6 (600 W)         | OK. One native cable, 360 W load.          |
| SSD (Gen5 x4, M.2 2280) to Board M.2_1 (CPU Gen5) | OK. Add a heatsink.                        |
| PSU (1200 W) to full system (~700 W peak)         | OK. About 490 W headroom.                  |
| Board (ATX) to Case (up to E-ATX)                 | OK. Ample room.                            |

## Case Cooling and Radiator Support

Radiator support by location (official Thermaltake):

| Location         | Max radiator |
| ---------------- | ------------ |
| Front            | up to 420 mm |
| Motherboard side | up to 420 mm |
| Rear             | up to 420 mm |
| Top              | up to 240 mm |
| Bottom           | up to 360 mm |

Fan support by location:

| Location         | Fans                               |
| ---------------- | ---------------------------------- |
| Top              | 2x 120 mm or 2x 140 mm             |
| Front            | 3x 120 mm, 3x 140 mm, or 2x 200 mm |
| Bottom           | 3x 120 mm or 3x 140 mm             |
| Rear             | 3x 120 mm, 3x 140 mm, or 2x 200 mm |
| Motherboard side | 3x 120 mm or 3x 140 mm             |

Thickness note: Thermaltake warns that "420 mm radiators over 27 mm in thickness
may have issues with compatibility on multi radiator configurations." This
applies only to custom multi-radiator loops. A single 38 mm AIO radiator fits
fine, and the CTE chassis is designed for large, thick radiators.

## Cooling Configuration and Fan Plan

### How the case moves air

The rotated CTE layout gives the CPU and GPU separate cold-air intakes. Per
Thermaltake's own thermal validation report and independent reviews:

- Intake: front, rear, and bottom. The rear is an intake here, not the usual
  exhaust, and feeds cold air straight onto the rear-mounted GPU. Rear plus
  bottom is the GPU's dedicated cold-air path.
- Exhaust: top (heat rises out). The motherboard-side panel can run as intake or
  exhaust.
- The 3 preinstalled CT140 fans ship as front intake, rear intake, top exhaust.

### Recommended AIO placement: front, as intake

Mount the ARCTIC 420 in the front as intake. This is the configuration
Thermaltake validated, it preserves the full 420 mm GPU clearance (a radiator in
the GPU path cuts max GPU length to 370 mm), and AIO-placement testing on a
matching 285K + RTX 5080 360 W rig measured front/side mounting about 3 C cooler
on the CPU than top. The 285K's ~250 W is trivial for a 420 mm radiator, so CPU
temperature is a non-issue either way.

Side-mounted-as-exhaust is a valid alternative but not a proven optimum (see Myth
check). It places the radiator in the GPU chamber and cuts GPU clearance to
370 mm, so prefer front mounting here.

### Recommended fan layout (front AIO)

| Location         | Fans             | Direction | Purpose                          |
| ---------------- | ---------------- | --------- | -------------------------------- |
| Front            | 3x P14 Pro (AIO) | Intake    | CPU radiator, coldest air        |
| Rear             | 3x P14 Pro       | Intake    | GPU cold-air path                |
| Bottom           | 3x P14 Pro       | Intake    | GPU cold-air path                |
| Top              | 2x P14 Pro       | Exhaust   | Evacuate CPU and case heat       |
| Motherboard side | open             | -         | Not populated; 2 spare fans held |

This fully populates the GPU's rear plus bottom intake (the priority for a hot
air-cooled card) and runs slightly positive pressure to limit dust.

### Fan count

The build runs 11 fans: the AIO's 3 front P14 Pro plus 8 case P14 Pro (rear 3,
bottom 3, top 2). That uses 8 of the 10 P14 Pro purchased; the other 2 are
spares. The 3 stock CT140s come out and are kept as spares.

The motherboard-side 3-fan bank stays open. Independent testing (KitGuru) found
this case is not airflow-limited, so the side bank is optional and would add only
a marginal thermal gain.

### Fan model and noise

- Case fans: ARCTIC P14 Pro PST (140 mm), the same fan the AIO carries on its
  radiator, so the whole system runs one fan model with one acoustic signature.
  It leads the compared fans on airflow (110 CFM) and static pressure
  (5.2 mmH2O) at the lowest price per fan (see build-report.md).
- Noise strategy: more 140 mm fans at low RPM beat fewer at high RPM, because fan
  noise climbs steeply with RPM. Set a gentle curve, roughly 600 to 900 RPM idle
  ramping to 1200 to 1400 RPM under load; the P14 Pro's airflow lets it stay low.

### Fan control

The AIO daisy-chains its pump, 3 radiator fans, and VRM fan onto one cable to a
single header (CPU_FAN or AIO_PUMP). The 8 case fans run from the ARCTIC Case Fan
Hub (ACFAN00175A): 10 PWM ports, SATA-powered from the PSU, all driven by one
chassis-fan PWM signal so the case fans turn as a single synchronized zone. The 8
P14 Pro draw about 2.8 A, well under the hub's 4.5 A input. Net: one board header
for the AIO, one for the hub.

### GPU orientation caveat

The CTE layout mounts the GPU vertically. Independent testing (igor'sLAB) found a
heat-pipe hotspot problem in this orientation on some air-cooled cards (hotspot
up to about 106 C, roughly 40 C above ambient, on an RX 6900 XT and an
RTX 3070 Ti), resolved by orienting the case horizontally or using a water block.
It is card-dependent (an RX 6600 was unaffected), and modern vapor-chamber
coolers tolerate it better. Monitor the RTX 5080's hotspot and memory-junction
temperature under sustained load; the recommended fan plan already maximizes the
GPU's cold-air intake, which is the main mitigation.

### Myth check: side-exhaust AIO claims

Three widely repeated claims about this case do not survive the primary sources:

- "High-end GPUs benefit more from side exhaust than intake fans" (often citing
  an RTX 4080): unsupported. The RTX 4080 figure traces to review benches run as
  intake, not to any side-exhaust test. The GPU is cooled by its own rear and
  bottom intake, not by the CPU AIO's exhaust.
- "Side-mounted AIO as exhaust is optimal or Thermaltake-official": inaccurate.
  The "official Side = Exhaust" spec is a mislabeled forum post. Thermaltake's
  page describes the side as an intake, and every measured configuration (vendor
  and igor'sLAB) runs the radiator as intake. No professional front-versus-side
  test exists.
- "Side AIO isolates CPU heat and improves GPU temps": partly true. The CPU and
  GPU heat isolation is real, but it comes from the rotated layout, not from
  side-mounting the AIO, and the GPU benefit is unmeasured (one test found a CPU
  AIO left the GPU about 3 C warmer).

Front-intake AIO with a fully populated GPU intake path is the better-supported
setup.

## Recommended Assembly Layout

- GPU: install in the primary PCIe 5.0 x16 slot (CPU-attached, the top slot).
  This is a direct board mount with no riser cable. The CTE layout rotates the
  entire motherboard, so the card keeps its native slot connection. A riser is
  needed only for the optional vertical (showcase) orientation, which is not
  recommended for this card: it would require a separately purchased PCIe 5.0
  riser cable (the case ships only the bracket), place the 3.5-slot card against
  the side glass, and restrict airflow on a 360 W GPU.
- SSD: install the Crucial T710 in M.2_1 (CPU PCIe 5.0 x4, dedicated). Use the
  board's Gen5 M.2 heatsink. Keep M.2_3 and M.2_4 empty so the GPU slot stays at
  x16. Extra drives go in M.2_2 (CPU Gen4) or M.2_5 / M.2_6 (chipset Gen4).
- RAM: install both DIMMs in the two ASUS-specified slots (typically A2 and B2)
  to keep 1 DIMM per channel. Enable XMP, set Gear 2, and update to the latest
  BIOS before targeting DDR5-8400. A second pair later (4 slots) will not sustain
  8400 and drops to ~6400; that is the capacity-over-speed tradeoff covered in the
  RAM spec.
- AIO: mount the 420 mm radiator in the front as intake. It keeps GPU clearance
  at the full 420 mm and matches Thermaltake's validated configuration. See
  Cooling Configuration and Fan Plan for the full fan layout, fan count, and why
  side-exhaust is not the better choice here.
- PSU: route the PSU's native 12V-2x6 cable straight to the GPU. Do not use the
  GPU's bundled 8-pin adapter. Seat the connector fully until it clicks.

## Power Budget

| Rail                        | Draw                                     |
| --------------------------- | ---------------------------------------- |
| CPU (max turbo, PL2)        | up to 250 W                              |
| GPU (TGP)                   | 360 W (transient spikes 500 W+)          |
| Board, RAM, SSD, fans, pump | ~80 to 100 W                             |
| Sustained system peak       | ~660 to 710 W                            |
| PSU capacity                | 1200 W                                   |
| Headroom                    | ~490 W (system runs near 55 to 60% load) |

The 1200 W unit sits near its peak-efficiency load band and absorbs RTX 5080
transient spikes without issue. This exceeds NVIDIA's 850 W guidance with margin.

## Build Caveats and Risks

1. DDR5-8400 is an overclock, not a guaranteed speed. It depends on the memory
   controller (varies by chip), a current BIOS, Gear 2, and the 1DPC 2-DIMM
   layout. If unstable, step down to DDR5-8000, 7600, or the native 6400. Two
   DIMMs hold 8400; adding a second pair for capacity drops it to ~6400 (see the
   RAM spec upgrade path).
2. The Gen5 SSD needs a heatsink. This "-01" SKU ships without one. Use the
   motherboard's Gen5 M.2 heatsink or the drive will thermally throttle.
3. GPU lane sharing: keeping M.2_3 and M.2_4 empty preserves the GPU at
   PCIe 5.0 x16. Populating either drops it to x8.
4. Airflow planning: the CTE rotated layout moves heat vertically. Set the case
   P14 Pro fans and the AIO fans for front, rear, and bottom intake with top
   exhaust. Confirm fan orientation during assembly.
5. 12V-2x6 seating: fully seat the connector to avoid the known melting risk on
   high-power NVIDIA cards. The native PSU cable is preferred over adapters.
6. GPU orientation: the CTE layout mounts the GPU vertically, which can cause
   heat-pipe hotspot issues on some air-cooled cards. Monitor hotspot and memory
   temperatures; the recommended fan plan already maximizes rear and bottom
   intake, the main mitigation. See Cooling Configuration and Fan Plan.
7. Fan control: 11 fans on an 8-header board is handled by the ARCTIC Case Fan
   Hub (SATA-powered, 10-port). All 8 case fans run off it as one zone; the AIO
   uses one board header.
8. Thermal paste: the build uses Noctua NT-H2; the AIO's included MX-6 is
   the spare. The NT-H2 AM5 Edition's paste guard is shaped for the AMD AM5 IHS and
   does not fit the 285K's LGA1851, so it goes unused. The compound and the 3
   cleaning wipes are socket-agnostic.
9. Fan mounting: the P14 Pro mounting holes are tight, and the screws are hard to
   drive once a fan is held against the case. Pre-run each screw through the fan on
   a flat surface, pressing firmly to avoid stripping the head, before mounting the
   fan to the case.

## Sources

- Intel ARK: Core Ultra 9 285K (SKU 241060)
- ASUS ROG Maximus Z890 Hero official specification page
- Gigabyte GV-N5080GAMING OC-16GD product page; NVIDIA GeForce RTX 5080 page;
  TechPowerUp review
- Corsair CMKC48GX5M2X8400C40 product page; Rambus DDR5 CKD reference
- Crucial T710 (CT4000T710SSD8) product page; StorageReview, HotHardware,
  Tom's Hardware, TechPowerUp reviews
- ASUS ROG Strix 1200W Platinum product page; Cybenetics / HWBusters review
- ARCTIC Liquid Freezer III Pro 420 (ACFRE00181A) spec sheet; Tom's Hardware,
  KitGuru, HWCooling reviews
- Thermaltake CTE C750 Air official specification page; KitGuru review
- Thermaltake CTE C750 Air System Thermal Test Report (PDF); igor'sLAB,
  TechPowerUp, Guru3D, PC Gamer CTE C750 reviews
- Noctua AIO radiator placement guide (top vs front/side); ARCTIC P14 Pro PST
  (ACFAN00319A) and ARCTIC Case Fan Hub (ACFAN00175A) product pages
