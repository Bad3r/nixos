# Flashing and recovering the FC660C controller

The controller flashes over its Atmel DFU bootloader, entered with a
physical button, not a key combo. This covers entering the bootloader,
flashing a new build, and recovering from a bad or interrupted flash.

## Entering the bootloader

Press the reset button on the back of the controller, where the stock
controller's DIP switches were. The board drops off `4853:660c` and
re-enumerates as `03eb:2ff4` (Atmel DFU); confirm with:

```sh
lsusb -d 03eb:2ff4
```

See [identification.md](identification.md#hardware-identity-bootloader-mode)
for what that vendor:product pair means. No unlock combo, GUI action, or
software step is needed to enter the bootloader; it is a hardware button.

## Flashing from a vial-qmk checkout

```sh
git clone --branch vial https://github.com/vial-kb/vial-qmk
cd vial-qmk
# press the reset button now
make fc660c:vial:dfu
```

This builds the upstream `vial` base keymap and flashes it over DFU. It is not
the `vial-gaming` overlay used by the unit documented here. To reproduce that
image, apply [firmware/config.h](firmware/config.h) and
[firmware/rules.mk](firmware/rules.mk) to a copied `vial-gaming` keymap, then
run `make fc660c:vial-gaming:dfu` from the checkout. The NixOS-specific toolchain
and overlay setup are in [firmware/README.md](firmware/README.md).

That invocation does not work as written on NixOS. vial-qmk ships no Nix
expression, its bundled `lib/python/qmk/math.py` calls `ast.Num` (removed in
Python 3.12) while nixpkgs' `qmk` runs on 3.14, and `nixpkgs#avrlibc` is
unsupported on `x86_64-linux`. See [firmware/README.md](firmware/README.md) for
a working toolchain invocation, the local keymap overlay, and the flash budget
this MCU imposes.

## Flashing with dfu-programmer directly

Without a vial-qmk checkout, flash a prebuilt `.hex` directly:

```sh
# press the reset button first
dfu-programmer atmega32u4 erase --force
dfu-programmer atmega32u4 flash <firmware>.hex
dfu-programmer atmega32u4 reset
```

Drop `--force` on dfu-programmer 0.6.x; it is required on newer releases.
The fc660c NixOS module installs `dfu-programmer` and `usbutils` directly (see
[configuration.md](configuration.md#nixos-module)), so `dfu-programmer` and
`lsusb` are already on `PATH` wherever the module is enabled. nixpkgs pins it at
1.1.0 and also
carries `avrdude` 8.2 at the same locked commit if a workflow needs it
instead; the module does not install `avrdude`.

The [flash helper](firmware/flash-fc660c.sh) checks that both commands are
available before inspecting the controller. Outside a host with the module
enabled, provide `dfu-programmer` and `lsusb` through the corresponding
packages before invoking it; it will not resolve an unpinned fallback during a
flash.

## Permissions

Neither `dfu-programmer` nor `dfu-util` in nixpkgs ships udev rules (checked
directly against both packages' derivations: neither references `udev`
anywhere), so upstream QMK's own instructions default to root
(`sudo make fc660c:default:dfu`). The fc660c NixOS module
(see [configuration.md](configuration.md#nixos-module)) closes that gap
itself: alongside its Vial-serial rule, its udev rule file carries a second
line scoped to the Atmel DFU identity (`03eb:2ff4`) granting
`TAG+="uaccess"`, the same line `qmk-udev-rules` 0.27.13 ships for that PID.
With the module enabled, both `dfu-programmer` and `make ... :dfu` reach the
bootloader without `sudo`. Root is only needed when flashing from a system
where the module is not active, such as a NixOS installer ISO or a
non-NixOS machine.

## Verifying after a flash

Re-run the normal-mode identification commands from
[identification.md](identification.md#hardware-identity-normal-operation).
The board should reappear as `4853:660c`; check `iSerial` (or `Uniq` in
`/proc/bus/input/devices`) to confirm which firmware landed: `vial:f64c2b3c`
for this keymap, absent or different for a plain TMK or VIA-only build (see
[Telling firmware apart](identification.md#telling-firmware-apart)).

## Recovering from a bad or interrupted flash

The reset button always re-enters the DFU bootloader, regardless of
application firmware state: the bootloader lives in a separate, protected
flash section that `dfu-programmer erase`/`flash` never touches. A bad or
interrupted application flash cannot brick the board past that point.
Recovery is the same three commands as a normal flash: press reset, erase,
flash a known-good `.hex`, reset.
