#!/usr/bin/env bash
# Flash a firmware image to the Hasu FC660C Alt Controller (ATmega32U4, Atmel DFU).
#
# Usage: flash-fc660c.sh <path-to-hex>
#
# Run as a normal user. Elevation is applied per dfu-programmer call, so wrapping
# the whole script in sudo is unnecessary. With hardware.keyboards.fc660c.enable
# set, the module's 03eb:2ff4 udev rule grants uaccess and no sudo is needed at
# all; NEED_SUDO below detects that.
set -euo pipefail

HEX="${1:-}"
if [ -z "$HEX" ]; then
  echo "Usage: $(basename "$0") <path-to-hex>" >&2
  exit 2
fi

if [ ! -f "$HEX" ]; then
  echo "No such firmware file: $HEX" >&2
  exit 1
fi

# Intel HEX always terminates with the EOF record; catches a truncated build.
if [ "$(tail -1 "$HEX" | tr -d '\r\n')" != ":00000001FF" ]; then
  echo "$HEX does not end in an Intel HEX EOF record. Refusing to flash." >&2
  exit 1
fi

if command -v dfu-programmer >/dev/null 2>&1; then
  DFU=(dfu-programmer)
else
  DFU=(nix run nixpkgs#dfu-programmer --)
fi

if ! lsusb -d 03eb:2ff4 >/dev/null 2>&1; then
  echo "Controller is not in DFU mode." >&2
  echo "Press the reset button on the back of the controller, then re-run." >&2
  exit 1
fi

# The udev rule grants uaccess to the bootloader; fall back to sudo without it.
NEED_SUDO=()
if ! "${DFU[@]}" atmega32u4 get bootloader-version >/dev/null 2>&1; then
  NEED_SUDO=(sudo)
fi

echo "Flashing: $HEX"
echo "sha256:   $(sha256sum "$HEX" | cut -d' ' -f1)"
echo

echo "==> erasing"
"${NEED_SUDO[@]}" "${DFU[@]}" atmega32u4 erase --force
echo "==> flashing"
"${NEED_SUDO[@]}" "${DFU[@]}" atmega32u4 flash "$HEX"
echo "==> resetting"
"${NEED_SUDO[@]}" "${DFU[@]}" atmega32u4 reset

sleep 2
echo "==> verifying"
if lsusb -d 4853:660c; then
  echo "OK: keyboard re-enumerated"
else
  echo "Keyboard did not re-enumerate. Press the reset button and re-run to retry." >&2
  exit 1
fi
