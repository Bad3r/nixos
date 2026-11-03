# sbx GUI input and control

[`sbx`](README.md) captures and drives the display of a sandbox on a [GUI base](bases.md#gui-bases).

| Verb                                    | Effect                                 |
| --------------------------------------- | -------------------------------------- |
| `screenshot <name> [--ocr]`             | display to a new file, opt. OCR        |
| `key <name> <chord>...`                 | press each chord, such as `ctrl+alt+t` |
| `type <name> [--mode keys] <text>`      | type text; newline is `enter`          |
| `mouse <name> --to X,Y [--click B]`     | move the pointer, opt. click           |
| `window wait <name> --name/--class RE`  | wait for a visible window              |
| `window focus <name> --id ID/--name RE` | activate a window                      |
| `window list <name>`                    | describe every visible window          |

- Every verb but `screenshot` refuses a sandbox on any other base with `no-display`.
- Malformed input fails with `invalid-argument` before anything reaches the guest, except a `type` text with too many characters outside the keyboard layout, which `sbx` counts against the guest's keymap.
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
- A call past the chord cap fails with `invalid-argument` before any key goes out.

## Text

- `type` runs `xdotool type --clearmodifiers --file -` through qemu-ga as the user `sbx` on `DISPLAY=:0`, with the text on its stdin.
- xdotool releases Caps Lock and held modifiers around the text.
- Characters outside the keyboard layout are bound first, two to a spare keycode, through `xmodmap`, and stay bound.
  xdotool's own binding lasts milliseconds, and a busy client that reads the key press later drops the character.
  The root window's `_SBX_TYPE_KEYCODES` property lists the keycodes `sbx` bound, oldest first, and later texts rebind the oldest first.
  A text that rebinds keycodes waits a second first, so a client up to that far behind still reads the previous text by its own characters.
  A text that needs more spare keycodes than are free fails with `invalid-argument`; xdotool keeps the lowest empty keycode.
  Any X client in the guest can read the bound characters from the keymap until a later text rebinds their keycodes.
  A sandbox made from a base built before this binding lacks `xmodmap` and fails such a text with `guest-command`; rebuild the base.
- Newline presses Enter and tab presses Tab; any other control character fails, as does text past the length cap.
- The journal records how many characters `type` sent, never the text.
  A refusal names the positions of the characters at fault, never the characters.
- `--mode keys` (MCP `mode: keys`) sends US-layout keycodes from the host instead, for a screen before X starts.
  It refuses characters outside that layout, and the guest's layout must be US for the characters to come out right.
- Keys mode reads `/sys/class/leds/input*::capslock/brightness` through qemu-ga first and, when the LED is lit, presses Caps Lock before and after the text.

## Pointer and windows

`mouse`, `window wait`, `window focus`, and `window list` run `xdotool` scripts through qemu-ga as the user `sbx` on `DISPLAY=:0`.
The domain has no tablet device and no USB controller, so the host sends no pointer events of its own.

- `mouse --to X,Y` moves the pointer to a display pixel and waits until it got there.
  `--click left|middle|right` clicks there, and `--double` clicks twice, left unless `--click` names a button.
  A point off the display fails with `invalid-argument`.
- `window wait` polls until X answers, then until a visible window's name (`--name`) or class (`--class`) matches.
  It fails with `window-timeout` after `--timeout`, 30 s unless given.
- Patterns are POSIX extended regular expressions, matched case-insensitively; one that does not compile fails with `invalid-argument`.
- `window focus` activates a window by `--id`, or the first visible one whose name matches `--name`, and fails with `no-window` when there is none.
- Each window comes back as `{id, name, geometry: {x, y, width, height}}`, in display pixels from the top left.
  `window list` includes the window manager's own windows.
- The guest prints these descriptions, so `sbx` parses them strictly and fails with `agent-reply` on anything else.
  Window names are the guest's text: treat them as untrusted.
- MCP names the verbs `mouse`, `window_wait`, `window_focus`, and `window_list`, with `x` and `y` for `--to`, `title` for `--name`, and `class` and `id` as given.
- The journal records each `mouse` and `window focus`.
