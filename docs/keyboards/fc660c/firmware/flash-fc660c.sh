#!/usr/bin/env bash
# Flash a firmware image to the Hasu FC660C Alt Controller (ATmega32U4, Atmel DFU).
#
# Usage: flash-fc660c.sh <path-to-hex>
#
# The NixOS module supplies dfu-programmer and lsusb; no package-resolution
# fallback is used during a flash.
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

if ! command -v lsusb >/dev/null 2>&1; then
  echo "lsusb not found. Enable hardware.keyboards.fc660c, or run" >&2
  echo "inside 'nix shell nixpkgs#usbutils'." >&2
  exit 1
fi

if ! command -v dfu-programmer >/dev/null 2>&1; then
  echo "dfu-programmer not found. Enable hardware.keyboards.fc660c, or run" >&2
  echo "inside 'nix shell nixpkgs#dfu-programmer'." >&2
  exit 1
fi
DFU=(dfu-programmer)

check_lsusb() {
  local output
  if ! output="$(lsusb 2>&1)"; then
    echo "lsusb failed while inspecting USB devices: $output" >&2
    return 1
  fi
}

if ! check_lsusb; then
  exit 1
fi

if ! lsusb -d 03eb:2ff4 >/dev/null 2>&1; then
  echo "Controller is not in DFU mode." >&2
  echo "Press the reset button on the back of the controller, then re-run." >&2
  exit 1
fi

# The udev rule grants uaccess to the bootloader; fall back to sudo only when the
# device is still present but the unprivileged probe cannot reach it.
NEED_SUDO=()
if ! "${DFU[@]}" atmega32u4 get bootloader-version >/dev/null 2>&1; then
  if ! check_lsusb; then
    exit 1
  fi
  if ! lsusb -d 03eb:2ff4 >/dev/null 2>&1; then
    echo "Controller left DFU mode while checking device access." >&2
    echo "Press the reset button on the back of the controller, then re-run." >&2
    exit 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "dfu-programmer cannot access the controller and sudo was not found." >&2
    echo "Reload the udev rules or install sudo, then re-run." >&2
    exit 1
  fi
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
verification_attempts=5
for ((attempt = 1; attempt <= verification_attempts; attempt++)); do
  if ! check_lsusb; then
    exit 1
  fi
  if lsusb -d 4853:660c; then
    echo "OK: keyboard re-enumerated"
    exit 0
  fi
  if [ "$attempt" -lt "$verification_attempts" ]; then
    sleep 1
  fi
done

echo "Keyboard did not re-enumerate after ${verification_attempts} checks. Press the reset button and re-run to retry." >&2
exit 1
