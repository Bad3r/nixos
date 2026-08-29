# Identifying the FC660C controller and firmware

Use these commands to confirm a board is the Hasu Alt Controller rather than a
stock FC660C controller, to tell Vial firmware apart from stock TMK or plain
QMK/VIA, and to resolve a specific HID interface to its current hidraw node.
Every command below is bus-path-independent except where noted; hidraw
numbers and USB bus paths are assigned at enumeration time and are not stable
across reboots or replugs, so resolve nodes by content (vendor/product ID,
interface path), never by an assumed number. Example output below was
captured on `songbird` on 2026-08-29 and will differ in bus path and hidraw
numbers on any other boot.

## Hardware identity, normal operation

```sh
lsusb -d 4853:660c
```

```
Bus 003 Device 007: ID 4853:660c Hasu FC660C
```

`0x4853` is ASCII `HS` (Hasu); `0x660C` is the board. Both values come from
TMK's `keyboard/fc660c` config and are inherited unchanged by the QMK and
Vial ports, so the vendor:product pair alone does not distinguish which of
the three firmwares is flashed; see [Telling firmware apart](#telling-firmware-apart)
below.

For the full descriptor:

```sh
lsusb -v -d 4853:660c
```

`Report Descriptors: ** UNAVAILABLE **` in that output is expected for an
unprivileged, non-detached read; use the hidraw sysfs node
(`report_descriptor`, below) to read descriptor bytes instead.

Key fields from the device descriptor, all reproducible from the command
above without a bus path:

| Field       | Value                          |
| ----------- | ------------------------------ |
| `bcdUSB`    | `2.00`                         |
| `bcdDevice` | `1.00`                         |
| `iSerial`   | `vial:f64c2b3c`                |
| Speed       | Full Speed (12 Mbps)           |
| Power       | Bus powered, `bMaxPower 500mA` |
| Interfaces  | 3                              |

To resolve the sysfs device directory without hardcoding a bus path (the
example below, `3-8.3`, is this boot's path only):

```sh
for d in /sys/bus/usb/devices/*/idVendor; do
  [ "$(cat "$d" 2>/dev/null)" = "4853" ] && dirname "$d"
done
```

Or skip sysfs entirely and read the kernel input layer, which needs no bus
path at all because it is a flat list keyed by name:

```sh
grep -A3 'Name="Hasu FC660C"$' /proc/bus/input/devices
```

```
N: Name="Hasu FC660C"
P: Phys=usb-0000:80:14.0-8.3/input0
S: Sysfs=/devices/pci0000:80/0000:80:14.0/usb3/3-8/3-8.3/3-8.3:1.0/0003:4853:660C.0004/input/input1
U: Uniq=vial:f64c2b3c
```

`Uniq` mirrors `iSerial`, so this alone is enough to confirm identity and
firmware family without touching sysfs or USB tooling.

## Hardware identity, bootloader mode

Pressing the reset button (back of the controller, where the stock
controller's DIP switches were) drops the board off `4853:660c` and it
re-enumerates as an Atmel DFU device:

```sh
lsusb -d 03eb:2ff4
```

`0x03eb` is Atmel/Microchip; `0x2ff4` specifically identifies an ATmega32U4
DFU bootloader, independent of what firmware (or vendor) is on the chip. No
special command is needed to leave bootloader mode: a power cycle, a host
reset command, or a completed flash returns the board to `4853:660c`.

## The three HID interfaces

All three interfaces bind to the kernel's generic `usbhid` driver. hidraw
numbers below were captured this boot; resolve by interface path (shown in
[Resolving a hidraw node](#resolving-a-hidraw-node)), not by these numbers.

| Iface | Class/subclass/protocol | hidraw (this boot) | Input node name(s)                                                                                        | Role                                                                     |
| ----- | ----------------------- | ------------------ | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 0     | 03/01/01                | hidraw3            | `Hasu FC660C`                                                                                             | Boot-protocol keyboard, 68-byte report descriptor                        |
| 1     | 03/00/00                | hidraw4            | (none; no input node registers for this interface)                                                        | Raw HID config channel, 34-byte descriptor, EP `0x82` IN + EP `0x03` OUT |
| 2     | 03/00/00                | hidraw5            | `Hasu FC660C Mouse`, `Hasu FC660C System Control`, `Hasu FC660C Consumer Control`, `Hasu FC660C Keyboard` | Combined mouse/media/NKRO-keyboard collection, 182-byte descriptor       |

Interface 2 registers four input nodes, not three: alongside mouse, system
control, and consumer control, it carries a second keyboard usage-page
collection (`Hasu FC660C Keyboard`, with `sysrq kbd leds` handlers like
interface 0's boot keyboard) multiplexed onto the same interface by report
ID. Interface 1 registers no input node at all; it exists purely as a
bidirectional vendor data channel, which is exactly what a config-protocol
interface should look like.

### Resolving a hidraw node

```sh
for dev in /sys/class/hidraw/hidraw*; do
  p=$(udevadm info -q path -p "$dev" 2>/dev/null)
  case "$p" in *4853:660C*) echo "$dev -> $p" ;; esac
done
```

The interface number is the segment after `:1.` in the printed path (for
example `.../3-8.3:1.1/...` is interface 1).

## Confirming interface roles from the report descriptor

Once a hidraw node is resolved, dump its report descriptor directly from
sysfs. This needs no root and no bus path:

```sh
xxd /sys/class/hidraw/hidraw4/device/report_descriptor
```

Interface 1 (34 bytes, matching `wDescriptorLength` from the USB descriptor):

```
06 60 FF 09 61 A1 01 09 62 15 00 26 FF 00 95 20
75 08 81 02 09 63 15 00 26 FF 00 95 20 75 08 91
02 C0
```

| Bytes            | Meaning                                |
| ---------------- | -------------------------------------- |
| `06 60 FF`       | Usage Page (Vendor Defined `0xFF60`)   |
| `09 61`          | Usage (`0x61`)                         |
| `A1 01`          | Collection (Application)               |
| `09 62`          | Usage (`0x62`)                         |
| `15 00 26 FF 00` | Logical Minimum 0, Logical Maximum 255 |
| `95 20 75 08`    | Report Count 32, Report Size 8         |
| `81 02`          | Input (Data, Variable, Absolute)       |
| `09 63`          | Usage (`0x63`)                         |
| `15 00 26 FF 00` | Logical Minimum 0, Logical Maximum 255 |
| `95 20 75 08`    | Report Count 32, Report Size 8         |
| `91 02`          | Output (Data, Variable, Absolute)      |
| `C0`             | End Collection                         |

Usage Page `0xFF60` / Usage `0x61` with matched 32-byte input and output
reports is the standard QMK `raw_hid.c` vendor channel, the transport VIA and
Vial both build on. Interface 0's descriptor (68 bytes) is a stock USB HID
boot-protocol keyboard (Usage Page Generic Desktop, Usage Keyboard,
modifier byte, 6-key rollover array, 5 LED output bits); interface 2's
descriptor (182 bytes) opens with a standard mouse collection (Usage Page
Generic Desktop, Usage Mouse, Report ID 2) followed by further Report
ID-keyed collections for system control, consumer control, and the NKRO
keyboard. Neither of those two is diagnostic of firmware identity the way
interface 1 is.

## Telling firmware apart

Three states are distinguishable from the USB descriptors alone, without
opening the case:

1. No interface exposing Usage Page `0xFF60` / Usage `0x61` at all: plain
   stock TMK. Verified directly against upstream: `tmk/tmk_keyboard`'s own
   `keyboard/fc660c` source (`config.h`, `fc660c.c`, `fc660c.h`, `Makefile`)
   defines no such interface anywhere, because raw HID vendor channels are a
   QMK-family convention TMK never adopted for this board.
2. The interface is present but `iSerial` (or `Uniq`) does not start with
   `vial:`: a QMK build with `VIA_ENABLE = yes` (VIA, not Vial).
3. The interface is present and `iSerial` starts with `vial:`: Vial
   (`VIAL_ENABLE = yes`, which this board's `rules.mk` also pairs with
   `VIA_ENABLE = yes`).

This unit is case 3.

### The `vial:f64c2b3c` serial is not a per-board ID

Every Vial keyboard ships the identical hardcoded serial string
`vial:f64c2b3c`; it is not derived from this specific controller. Vial's own
Linux udev documentation
(<https://get.vial.today/manual/linux-udev.html>) recommends matching on this
exact literal string so one rule covers every Vial keyboard a user owns:

```
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
```

The fc660c module does not use that rule verbatim, and neither should anything
else on a multi-user host. It matches every hidraw interface of the device,
including interfaces 0 and 2, which carry keystrokes; combined with
`GROUP="users"`, into which NixOS places every normal account, that lets any
local user read the live keystroke stream. See
[configuration.md](configuration.md#nixos-module) for the interface-scoped,
`uaccess`-only form the module ships instead.

The real per-board identity is the compiled-in `VIAL_KEYBOARD_UID`. It never
appears in a USB descriptor; it travels only over the raw-HID protocol on
interface 1, and is read by speaking that protocol (the Vial GUI or app does
this automatically on connect).

## Upstream source of this firmware

Repository: [`vial-kb/vial-qmk`](https://github.com/vial-kb/vial-qmk), default
branch `vial`, path `keyboards/fc660c/keymaps/vial`. Most recent commit
touching that path: `4152685a` (`4152685aa1a228760e70a4464fd19456eab434bf`),
2025-07-04, "Re-enable Caps Word and Layer Lock where possible. (#907)"
(touches `rules.mk`).

`config.h`:

```c
#define VIAL_KEYBOARD_UID {0x86, 0xDA, 0x85, 0x0E, 0x54, 0x70, 0xA0, 0xA2}
#define VIAL_UNLOCK_COMBO_ROWS { 1, 4 }
#define VIAL_UNLOCK_COMBO_COLS { 3, 14 }
#define VIAL_TAP_DANCE_ENTRIES 4
```

`rules.mk`:

```
VIA_ENABLE = yes
VIAL_ENABLE = yes
LTO_ENABLE = yes
QMK_SETTINGS = no
TAP_DANCE_ENABLE = yes
CONSOLE_ENABLE = no
EXTRALDFLAGS = -Wl,--relax
REPEAT_KEY_ENABLE = no
```

`vial.json` declares `"matrix": { "rows": 5, "cols": 16 }`, `"lighting": "none"`,
`vendorId` `0x4853`, `productId` `0x660C`. Its visual `keymap` layout array
marks exactly two keys with a distinct highlight color (`#777777`, versus
`#cccccc`/`#aaaaaa` for every other key): matrix positions `1,3` and `4,14`.
Those are the same two positions named in `VIAL_UNLOCK_COMBO_ROWS`/`COLS`
above; see [configuration.md](configuration.md#the-escenter-unlock-combo) for
the derivation of which physical keys those are and how to use the combo.
