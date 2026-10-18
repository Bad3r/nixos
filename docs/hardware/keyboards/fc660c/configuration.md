# Configuring the FC660C

Day-to-day key remapping happens entirely through Vial, live over USB, and no NixOS-managed keymap file exists.

- [Remapping with Vial](configuration-vial.md): the Vial workflow, the Esc+Enter unlock combo, and the actuation point that Vial cannot change.

## NixOS module

```nix
hardware.keyboards.fc660c.enable = true;
```

`modules/hardware/keyboards/fc660c.nix` declares the switch, and host wiring goes through the optional-module pattern in [Host Composition](../../../architecture/05-host-composition.md).
Enabling it turns the `vial` app row on as a prerequisite, installs `pkgs.dfu-programmer`, and ships a udev rule file scoped to this board.
`lsusb`, which the flash helper checks with, comes from the `usbutils` app row.

The rule file is the non-obvious part, because both upstream options are broader than this board:

- The nixpkgs `vial` package bundles `etc/udev/rules.d/92-viia.rules`, a world-writable (`0666`) rule on every hidraw node with no vendor, product, or serial qualifier.
  Installed through `services.udev.packages`, it would open security keys such as a YubiKey too.
- NixOS's `hardware.keyboard.qmk.enable` pulls `qmk-udev-rules`, whose `MODE="0660" GROUP="plugdev"` rule is narrower but still ends in an unqualified `KERNEL=="hidraw*"` catch-all.

The module's rule instead grants `TAG+="uaccess"` on one USB interface of one device, matched on vendor, product, serial, and interface number:

- Interface 01 only: it is the raw-HID config channel.
  Interfaces 00 and 02 are the boot and NKRO keyboards, so a whole-device match would hand out read access to the live keystroke stream.
- No `MODE` or `GROUP`: `uaccess` grants an ACL to the active seat user alone, whereas `GROUP="users"` would reach every normal account, since NixOS puts all of them in `users`.
- `ENV` rather than `ATTRS`: udev matches every `ATTRS` key of a rule on a single parent device (`man 7 udev`).
  `bInterfaceNumber` lives on the interface while `serial` lives on the device, so a combined `ATTRS` form matches nothing.
- The `ID_USB_*` properties it matches are set on the hidraw node itself.
- The serial match identifies the firmware, not the board, because Vial hardcodes `vial:f64c2b3c` on every Vial keyboard (see [identification.md](identification.md#the-vialf64c2b3c-serial-is-not-a-per-board-id)); vendor, product, and interface scope the rule to this device.

## Rule file order

The rule file name has to sort between 60 and 73:

- systemd's `73-seat-late.rules` is what promotes a `uaccess` tag into an ACL grant for the logged-in seat.
- udev evaluates rule files in filename order, in a single pass per device event.
  A tag added by a file sorting after `73-seat-late.rules` therefore arrives after that rule has run.
- `services.udev.extraRules` writes `/etc/udev/rules.d/99-local.rules`, which sorts after 73, so it is the wrong mechanism regardless of rule content.
  Vial's own project renamed its recommended rule file from `99-vial.rules` to `59-vial.rules` for the same reason.
- `60-persistent-hidraw.rules` imports the `usb_id` builtin that populates the `ID_USB_*` properties, so a file sorting below 60 evaluates before they exist and matches nothing.
- Vial's `59-` prefix works only because its rule matches `ATTRS`, which reads sysfs directly and needs no prior import.

The module therefore authors its own rule file in the 61..72 window, through a mechanism other than `extraRules`, rather than depending on the `vial` package or `hardware.keyboard.qmk.enable`.
It ships as `/etc/udev/rules.d/70-vial-fc660c.rules` through `services.udev.packages`.
The `vial` app module installs its package through `environment.systemPackages`, which NixOS never scans for udev rules, so the bundled `92-viia.rules` never takes effect.

## Bootloader access

The rule file carries a second line, scoped to the Atmel DFU bootloader identity `03eb:2ff4` rather than the Vial serial.
It is the line `qmk-udev-rules` ships for that PID, reproduced alone because the whole package would bring back its `hidraw*` catch-all.
With the module enabled, both the Vial GUI and the DFU bootloader are reachable without root, flashing included; see [flashing.md](flashing.md#permissions).
