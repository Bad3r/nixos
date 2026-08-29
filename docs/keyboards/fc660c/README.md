# FC660C (Hasu alt controller)

A Leopold FC660C (Topre capacitive, 66-key 60%) fitted with a Hasu (TMK) FC660C
Alt Controller: a solderless drop-in replacement PCB for the stock controller.
The stock board is not programmable; the alt controller replaces it with an
ATmega32U4 running QMK-family firmware, currently Vial. The unit documented
here is the keyboard attached to `songbird`, verified from sysfs, `lsusb -v`,
`/proc/bus/input/devices`, and live HID report descriptors on 2026-08-29.

## Quick facts

| Property                  | Value                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------- |
| Keyboard body             | Leopold FC660C, Topre capacitive, 66-key                                                                  |
| Controller                | Hasu (TMK) FC660C Alt Controller (solderless drop-in)                                                     |
| MCU                       | ATmega32U4                                                                                                |
| Bootloader                | Atmel DFU                                                                                                 |
| Bootloader / reset button | Back of the controller, where the stock DIP switches were                                                 |
| Firmware on this unit     | Vial (`vial-kb/vial-qmk`, `keyboards/fc660c/keymaps/vial`)                                                |
| USB identity, normal mode | `4853:660c` "Hasu FC660C", `bcdDevice 1.00`, full speed, bus powered                                      |
| USB identity, bootloader  | `03eb:2ff4` Atmel DFU (PID identifies an ATmega32U4 specifically)                                         |
| `iSerial`                 | `vial:f64c2b3c` (a universal Vial string, not a per-board ID; see [identification.md](identification.md)) |
| NixOS switch              | `hardware.keyboards.fc660c.enable` (`modules/hardware/keyboards/fc660c.nix`)                              |

## Documentation

| Page                                   | Read when                                                                                                                                               |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [identification.md](identification.md) | Confirming this is the Hasu Alt Controller, checking whether Vial or stock TMK firmware is flashed, or resolving a hidraw node to a specific interface. |
| [configuration.md](configuration.md)   | Enabling the NixOS module, remapping keys in Vial, using the Esc+Enter unlock combo, or hitting the actuation-point limitation.                         |
| [flashing.md](flashing.md)             | Reflashing firmware, or recovering an unresponsive or badly flashed controller.                                                                         |

## NixOS integration

`modules/hardware/keyboards/fc660c.nix` exposes `hardware.keyboards.fc660c.enable`.
Enabling it installs the Vial GUI, `dfu-programmer`, and a udev rule covering
both the board's normal-mode Vial interface and its Atmel DFU bootloader
identity, scoped narrowly enough to avoid either upstream option's blanket
hidraw rule. See [configuration.md](configuration.md#nixos-module) for the
rule content and how it differs from `hardware.keyboard.qmk.enable` and the
nixpkgs `vial` package's own bundled rule.

## External references

- TMK wiki: <https://github.com/tmk/tmk_keyboard/wiki>
- TMK fc660c source (plain, non-programmable-config firmware): <https://github.com/tmk/tmk_keyboard/tree/master/keyboard/fc660c>
- QMK port: <https://github.com/qmk/qmk_firmware/tree/master/keyboards/fc660c>
- vial-qmk (the fork this unit's firmware is built from): <https://github.com/vial-kb/vial-qmk>
- Vial manual: <https://get.vial.today/> and the Linux udev page <https://get.vial.today/manual/linux-udev.html>
- TMK project page: <http://www.tmk-kbd.com/tmk_keyboard/>
- Hasu's original build thread, "[TMK] FC660C Alt Controller": <https://geekhack.org/index.php?topic=88439.0>
- The 2017 group buy thread, "[GB] TMK FC660C Alt Controller": <https://geekhack.org/index.php?topic=88720.0>
- FCC filing for the stock Leopold FC660C (grantee Leopold Co., Ltd., granted 2013-01-28; schematic, part list, internal photos): <https://fccid.io/RPKFC660C>
- 1upkeyboards assembled USB-C controller (ships TMK by default per its listing; reflash with vial-qmk for Vial): <https://1upkeyboards.com/shop/controllers/fc660c-controller/>
