# Songbird hardware

## Parts

| Part          | Product                                 | Model number           |
| ------------- | --------------------------------------- | ---------------------- |
| CPU           | Intel Core Ultra 9 285K (Arrow Lake-S)  | BX80768285K            |
| Motherboard   | ASUS ROG Maximus Z890 Hero (ATX)        | 90MB1IX0-M0EAY0        |
| GPU           | ASUS GeForce RTX 5080 Noctua 16GB       | RTX5080-O16G-NOCTUA    |
| RAM           | Corsair Vengeance DDR5 CUDIMM 48GB 8400 | CMKC48GX5M2X8400C40    |
| SSD           | WD_BLACK SN8100 4TB PCIe 5.0 NVMe M.2   | WDS400T1X0M-00CMT0     |
| PSU           | ASUS ROG Strix 1200W Platinum           | ROG-STRIX-1200P-GAMING |
| CPU cooler    | Cooler Master MasterLiquid 360 Atmos    | MLX-D36M-A25PZ-R1      |
| Contact frame | Thermalright LGA1851-BCF (V2)           | TR-L18517BCFV2-BK      |
| Case          | Antec Flux SE (Mid Tower)               | UPC 0-761345-10177-6   |
| Case fans     | ARCTIC P14 Pro PST 140mm 5-pack         | ACFAN00319A            |
| Fan hub       | ARCTIC Case Fan Hub (10-port PWM, SATA) | ACFAN00175A            |
| Thermal paste | Noctua NT-H2 (3.5g, AM5 Edition)        | NT-H2 3.5g AM5         |

## Storage

| Disk | Model                      | Slot or bus                          | Serial          | Role                            |
| ---- | -------------------------- | ------------------------------------ | --------------- | ------------------------------- |
| A    | WD_BLACK SN8100 4TB        | M.2_1, CPU PCIe 5.0 (`0000:01:00.0`) | 252415800489    | NixOS root, swap, ESP           |
| S    | Samsung 860 PRO 2TB        | SATA, chipset (`0000:80:17.0`)       | S45DNF0K503930R | LUKS data volume at `/data`     |
| W    | WDC PC SN720 1TB           | M.2_2, CPU PCIe 4.0 (`0000:03:00.0`) | 192461421492    | Windows                         |
| P    | Samsung 970 PRO 512GB      | Chipset M.2 (`0000:82:00.0`)         | S469NF0K509254D | NTFS portal shared with Windows |
| none | Samsung MZHPV512HDGL-000L1 | AHCI M.2, chipset (`0000:87:00.0`)   | S1WUNYAH206176  | undeclared, reports 0 bytes     |

## Devices

| Device                   | Id          | Address               | Driver                |
| ------------------------ | ----------- | --------------------- | --------------------- |
| iGPU (Xe-LPG)            | `8086:7d67` | `0000:00:02.0`        | i915 (xe also loaded) |
| NPU 4                    | `8086:ad1d` | `0000:00:0b.0`        | intel_vpu             |
| Thunderbolt 4 / USB4     | `8086:7ec2` | `0000:00:0d.2`        | thunderbolt           |
| RTX 5080                 | `10de:2c02` | `0000:02:00.0`        | nvidia                |
| RTX 5080 HDMI audio      | `10de:22e9` | `0000:02:00.1`        | snd_hda_intel         |
| SATA controller (disk S) | `8086:7f62` | `0000:80:17.0`        | ahci                  |
| HDA controller           | `8086:7f50` | `0000:80:1f.3`        | snd_hda_intel         |
| Realtek RTL8126 5GbE     | `10ec:8126` | `0000:84:00.0`        | r8169                 |
| Intel I226-V 2.5GbE      | `8086:125c` | `0000:85:00.0`        | igc                   |
| Intel BE200 Wi-Fi 7      | `8086:272b` | `0000:86:00.0`        | iwlwifi               |
| Bluetooth (BE200)        | `8087:0036` | `usb-0000:80:14.0-14` | btusb                 |
| SupremeFX USB codec      | `0b05:1b7c` | `usb-0000:80:14.0-5`  | snd_usb_audio         |
| HyperX SoloCast mic      | `0951:170f` | `usb-0000:80:14.0-12` | snd_usb_audio         |
| YubiKey OTP+FIDO+CCID    | `1050:0407` | `usb-0000:80:14.0-13` | usbhid                |

## Constraints

- M.2_3 and M.2_4 stay empty; populating either drops the GPU slot from PCIe 5.0 x16 to x8.
- Disk A sits under the motherboard's M.2_1 heatsink; without it, sustained writes throttle.
- `/dev/nvmeN` indices reshuffle across boots. Address a drive by PCI address or serial, never by index.
- DDR5-8400 is an XMP profile above the CPU's native DDR5-6400. The fallback ladder is 8000, 7600, 6400; four DIMMs forfeit 8400.
- All fan and pump control runs through BIOS Q-Fan; no OS-side fan software exists.
- Use only the PSU's own modular cables. A cable from another unit can damage drives.
- The GPU's bundled anti-sag holder is installed; the case has no built-in GPU support.
- Remove the GPU with Q-Release Slim: lift the rear-I/O end at an angle, never pull it straight out.
- Each OS keeps its own ESP on its own disk, so Windows updates cannot touch the NixOS boot chain.

### UEFI settings

| Setting                          | Value                        | Why                        |
| -------------------------------- | ---------------------------- | -------------------------- |
| Secure Boot                      | Off                          | systemd-boot is unsigned   |
| Intel PTT                        | On                           | BitLocker                  |
| Above 4G Decoding, Resizable BAR | On                           | GPU requires it            |
| VT-x, VT-d                       | On                           | KVM                        |
| XMP                              | On                           | DDR5-8400 profile          |
| Fast Boot                        | Off                          | USB and initrd reliability |
| Boot order                       | systemd-boot on disk A first | default OS                 |

## Sources

External hardware record: [Bad3r/project-songbird](https://github.com/Bad3r/project-songbird).
