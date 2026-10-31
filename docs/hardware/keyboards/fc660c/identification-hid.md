# FC660C HID interfaces

The controller exposes three HID interfaces, and the raw HID one on interface 1 is what Vial talks to; the USB identity commands are in [identification.md](identification.md).
All three bind to the kernel's generic `usbhid` driver.
hidraw numbers are assigned at enumeration, so resolve a node by its interface path as below, never by an assumed number.

## The three HID interfaces

- Interface 0, class `03/01/01`: the boot-protocol keyboard, with a 68-byte report descriptor and the input node `Hasu FC660C`.
- Interface 1, class `03/00/00`: the raw HID config channel, with a 34-byte descriptor, endpoints `0x82` IN and `0x03` OUT, and no input node.
- Interface 2, class `03/00/00`: a combined mouse, media, and NKRO-keyboard collection, with a 182-byte descriptor.

Interface 2 registers four input nodes, not three: `Hasu FC660C Mouse`, `Hasu FC660C System Control`, and `Hasu FC660C Consumer Control`, plus a second keyboard usage-page collection, `Hasu FC660C Keyboard`.
That keyboard collection carries `sysrq kbd leds` handlers like interface 0's boot keyboard and shares the interface by report ID.
Interface 1 registers no input node at all; it is purely a bidirectional vendor data channel, the shape a config-protocol interface takes.

## Resolving a hidraw node

```sh
for dev in /sys/class/hidraw/hidraw*; do
  p=$(udevadm info -q path -p "$dev" 2>/dev/null)
  case "$p" in *4853:660C*) echo "$dev -> $p" ;; esac
done
```

The interface number is the segment after `:1.` in the printed path; for example, `.../3-8.3:1.1/...` is interface 1.

## Confirming interface roles from the report descriptor

Dump a resolved node's report descriptor directly from sysfs, with no root and no bus path; `hidraw<N>` is the node resolved above:

```sh
xxd /sys/class/hidraw/hidraw<N>/device/report_descriptor
```

Interface 1 prints 34 bytes, matching `wDescriptorLength` from the USB descriptor:

```text
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

Usage Page `0xFF60` and Usage `0x61` with matched 32-byte input and output reports are the standard QMK `raw_hid.c` vendor channel, the transport VIA and Vial both build on.

Interface 0's 68-byte descriptor is a stock USB HID boot-protocol keyboard: Usage Page Generic Desktop, Usage Keyboard, a modifier byte, a 6-key rollover array, and 5 LED output bits.
Interface 2's 182-byte descriptor opens with a standard mouse collection: Usage Page Generic Desktop, Usage Mouse, Report ID 2.
Report ID-keyed collections for system control, consumer control, and the NKRO keyboard follow it.
Neither of those two identifies the firmware the way interface 1 does.
