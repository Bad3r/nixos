# sbx GUI input

[`sbx`](README.md) captures and drives the display of a sandbox on a [GUI base](bases.md#gui-bases).

| Verb                               | Effect                                 |
| ---------------------------------- | -------------------------------------- |
| `screenshot <name> [--ocr]`        | display to a new file, opt. OCR        |
| `key <name> <chord>...`            | press each chord, such as `ctrl+alt+t` |
| `type <name> [--mode keys] <text>` | type text; newline is `enter`          |

- Every verb but `screenshot` refuses a sandbox on any other base with `no-display`.
- Malformed input fails with `invalid-argument` before anything reaches the guest.
- A guest helper that fails reports `guest-command` with its own message.

## Screenshots

- Each screenshot is named `screenshot-<UTC time to the microsecond>-<6 hex>.png`, or `.ppm` when the display hands out PPM, and never replaces a file.
- It lands in the sandbox's `xfer` directory, which `destroy` removes, or under `--to` (MCP `to`), a directory or a new file under the copy roots.
  A `--to` outside the roots or onto an existing file refuses before the capture.
  A `--to` naming a new file keeps that name whatever the image type.

## Keys

- `key` sends Linux keycodes from the host through libvirt, so it works before X starts.
- A chord joins key names with `+`; aliases such as `return`, `escape`, `pgup`, `control`, and `win` name the same keys.
  An unknown name fails with the list of known names and aliases.
- QEMU drops input past its queue, so `sbx` waits for each chord to land, about 20 ms a key.

## Text

- `type` runs `xdotool type --clearmodifiers --file -` through qemu-ga as the user `sbx` on `DISPLAY=:0`, with the text on its stdin.
- xdotool releases Caps Lock and held modifiers around the text, and types characters outside the keyboard layout through a spare keycode, so Unicode works.
- Newline presses Enter and tab presses Tab; any other control character fails, as does text past the length cap.
- The journal records how many characters `type` sent, never the text.
- `--mode keys` (MCP `mode: keys`) sends US-layout keycodes from the host instead, for a screen before X starts.
  It refuses characters outside that layout, and the guest's layout must be US for the characters to come out right.
- Keys mode reads `/sys/class/leds/input*::capslock/brightness` through qemu-ga first and, when the LED is lit, presses Caps Lock before and after the text.
