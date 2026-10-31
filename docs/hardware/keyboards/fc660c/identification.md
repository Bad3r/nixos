# Identifying the FC660C controller and firmware

These commands confirm a board is the Hasu Alt Controller rather than a stock FC660C controller, and tell Vial firmware apart from stock TMK or plain QMK/VIA.
`lsusb` comes from the `usbutils` app row.

Every command below is bus-path-independent except where noted, because hidraw numbers and USB bus paths are assigned at enumeration and change across reboots and replugs.
Resolve nodes by content, such as the vendor and product ID or the interface path, never by an assumed number.
The example output comes from `songbird` and differs in bus path and hidraw numbers on any other boot.

- [HID interfaces](identification-hid.md): the three interfaces, resolving a hidraw node, and reading the report descriptors.

## Hardware identity, normal operation

```sh
lsusb -d 4853:660c
```

```text
Bus 003 Device 007: ID 4853:660c Hasu FC660C
```

`0x4853` is ASCII `HS` (Hasu), and `0x660C` is the board.
Both values come from TMK's `keyboard/fc660c` config and carry over unchanged into the QMK and Vial ports.
The vendor:product pair alone therefore does not tell which of the three firmwares is flashed; see [Telling firmware apart](#telling-firmware-apart).

For the full descriptor:

```sh
lsusb -v -d 4853:660c
```

`Report Descriptors: ** UNAVAILABLE **` in that output is expected for an unprivileged, non-detached read; the hidraw sysfs node's `report_descriptor`, shown in [HID interfaces](identification-hid.md#confirming-interface-roles-from-the-report-descriptor), gives the descriptor bytes instead.

Key fields from the device descriptor, all reproducible from that command without a bus path:

| Field       | Value                          |
| ----------- | ------------------------------ |
| `bcdUSB`    | `2.00`                         |
| `bcdDevice` | `1.00`                         |
| `iSerial`   | `vial:f64c2b3c`                |
| Speed       | Full Speed (12 Mbps)           |
| Power       | Bus powered, `bMaxPower 500mA` |
| Interfaces  | 3                              |

To resolve the sysfs device directory without hardcoding a bus path, where the example `3-8.3` is one boot's path only:

```sh
for d in /sys/bus/usb/devices/*/idVendor; do
  [ "$(cat "$d" 2>/dev/null)" = "4853" ] && dirname "$d"
done
```

The kernel input layer needs no bus path at all, because it is a flat list keyed by name:

```sh
grep -A3 'Name="Hasu FC660C"$' /proc/bus/input/devices
```

```text
N: Name="Hasu FC660C"
P: Phys=usb-0000:80:14.0-8.3/input0
S: Sysfs=/devices/pci0000:80/0000:80:14.0/usb3/3-8/3-8.3/3-8.3:1.0/0003:4853:660C.0004/input/input1
U: Uniq=vial:f64c2b3c
```

`Uniq` mirrors `iSerial`, so this alone confirms identity and firmware family without touching sysfs or USB tooling.

## Hardware identity, bootloader mode

Pressing the reset button, on the back of the controller where the stock controller's DIP switches were, drops the board off `4853:660c`, and it re-enumerates as an Atmel DFU device:

```sh
lsusb -d 03eb:2ff4
```

`0x03eb` is Atmel/Microchip, and `0x2ff4` identifies an ATmega32U4 DFU bootloader, independent of the firmware or vendor on the chip.
Leaving bootloader mode needs no special command: a power cycle, a host reset command, or a completed flash returns the board to `4853:660c`.

## Telling firmware apart

The USB descriptors alone distinguish three states, without opening the case:

1. No interface exposes Usage Page `0xFF60` with Usage `0x61`: plain stock TMK.
   TMK's own `keyboard/fc660c` source defines no such interface, because raw HID vendor channels are a QMK-family convention TMK never adopted for this board.
2. The interface is present, but `iSerial` (or `Uniq`) does not start with `vial:`: a QMK build with `VIA_ENABLE = yes`, which is VIA, not Vial.
3. The interface is present, and `iSerial` starts with `vial:`: Vial, from `VIAL_ENABLE = yes`, which this board's `rules.mk` pairs with `VIA_ENABLE = yes`.

This unit is case 3.

### The `vial:f64c2b3c` serial is not a per-board ID

Every Vial keyboard ships the identical hardcoded serial string `vial:f64c2b3c`, which is not derived from this controller.
Vial's Linux udev documentation recommends one rule matching that literal string, so it covers every Vial keyboard a user owns, with `MODE="0660"`, `GROUP="users"`, and `uaccess`.

The fc660c module does not use that rule, and neither should anything else on a multi-user host.
It matches every hidraw interface of the device, including interfaces 0 and 2, which carry keystrokes.
Combined with `GROUP="users"`, which holds every normal NixOS account, it lets any local user read the live keystroke stream.
[configuration.md](configuration.md#nixos-module) has the interface-scoped, `uaccess`-only form the module ships instead.

The real per-board identity is the compiled-in `VIAL_KEYBOARD_UID`.
It never appears in a USB descriptor; it travels only over the raw HID protocol on interface 1, which the Vial GUI or app speaks automatically on connect.

## Upstream source and local overlay

The firmware on this unit starts from the `vial` keymap at `keyboards/fc660c/keymaps/vial` on the `vial` branch of [vial-kb/vial-qmk](https://github.com/vial-kb/vial-qmk).
The committed `vial-gaming` overlay in [firmware/](firmware/README.md) then replaces that base's `config.h` and `rules.mk`.

- The base `config.h` defines `VIAL_KEYBOARD_UID`, the unlock combo as `VIAL_UNLOCK_COMBO_ROWS { 1, 4 }` and `VIAL_UNLOCK_COMBO_COLS { 3, 14 }`, and `VIAL_TAP_DANCE_ENTRIES 4`.
- The base `rules.mk` enables `VIA_ENABLE`, `VIAL_ENABLE`, `LTO_ENABLE`, and `TAP_DANCE_ENABLE`, and disables `QMK_SETTINGS`, `CONSOLE_ENABLE`, and `REPEAT_KEY_ENABLE`.
- The base `vial.json` declares a 5-row, 16-column matrix, no lighting, and vendor and product IDs `0x4853` and `0x660C`.
- Its visual `keymap` layout marks exactly two keys with the highlight color `#777777`: matrix positions `1,3` and `4,14`, the two the unlock combo names.
  [configuration-vial.md](configuration-vial.md#the-escenter-unlock-combo) derives which physical keys those are and how to use the combo.

Vial's Linux udev documentation: <https://get.vial.today/manual/linux-udev.html>
