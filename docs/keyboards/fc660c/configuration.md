# Configuring the FC660C with Vial

Day-to-day key remapping happens entirely through Vial, live over USB; there
is no NixOS-managed keymap file. This page covers the NixOS switch that
grants access to the board, the Vial workflow itself, the Esc+Enter unlock
combo Vial requires for protected features, and the actuation-point
constraint that Vial cannot touch.

## NixOS module

```nix
hardware.keyboards.fc660c.enable = true;
```

Declared in `modules/hardware/keyboards/fc660c.nix`
(host wiring goes through the optional-module pattern in
[../../architecture/05-host-composition.md](../../architecture/05-host-composition.md)).
Enabling it installs the Vial GUI (`pkgs.vial`) and `pkgs.dfu-programmer`,
plus a udev rule scoped to this board rather than either upstream option's
broader rule. That scoping is the non-obvious part, for two reasons:

1. **Blanket rules exist upstream, and this module avoids both.** The
   nixpkgs `vial` package (0.7.5) bundles its own rule at
   `etc/udev/rules.d/92-viia.rules`:

   ```
   KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess", TAG+="udev-acl"
   ```

   Wiring that file into `services.udev.packages` world-opens every hidraw
   node on the system, security keys such as a YubiKey included, since the
   match has no vendor, product, or serial qualifier at all. NixOS's own
   `hardware.keyboard.qmk.enable` (which pulls `qmk-udev-rules` 0.27.13) is
   narrower, `MODE="0660" GROUP="plugdev"` instead of world-writable, but its
   rule still ends in an unqualified `KERNEL=="hidraw*"` catch-all rather
   than anything scoped to this board. The module here instead writes its
   own rule matched on the Vial serial, the same pattern Vial's own docs
   recommend (see [identification.md](identification.md#the-vialf64c2b3c-serial-is-not-a-per-board-id)):

   ```
   KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
   ```

2. **The rule file name has to sort before `73-seat-late.rules`.** That
   systemd-shipped rule file is what actually promotes a `TAG+="uaccess"`
   into a real ACL grant for the logged-in seat:

   ```
   TAG=="uaccess|xaccess-*", ENV{MAJOR}!="", RUN{builtin}+="uaccess"
   ```

   udev evaluates rule files in filename order in a single pass per device
   event. A tag added by a file that sorts *after* `73-seat-late.rules` is
   invisible to that line, because it already ran. NixOS's
   `services.udev.extraRules` writes to `/etc/udev/rules.d/99-local.rules`,
   which sorts after 73, so it is the wrong mechanism here regardless of
   rule content; this is exactly the mistake Vial's own project made and had
   to fix by renaming its recommended rule file from `99-vial.rules` to
   `59-vial.rules`.

Together these mean the module has to author its own rule file (a name
sorting below 73) through a mechanism other than `extraRules`, rather than
just depending on the `vial` package or `hardware.keyboard.qmk.enable`. The
rule ships as `/etc/udev/rules.d/59-vial-fc660c.rules` via
`services.udev.packages`. `pkgs.vial` itself goes only into
`environment.systemPackages`, which NixOS never scans for udev rules
(only `services.udev.packages` is read), so the package's own bundled
`92-viia.rules` is never installed and its blanket match never takes effect.

The rule file carries a second line, scoped to the Atmel DFU bootloader
identity (`03eb:2ff4`) rather than the Vial serial:

```
SUBSYSTEMS=="usb", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="2ff4", TAG+="uaccess"
```

This is the identical line `qmk-udev-rules` 0.27.13 ships for the same PID
(verified against its `util/udev/50-qmk.rules`, line 9). The module
reproduces just that one line instead of depending on the whole package,
which would also reintroduce the `hidraw*` catch-all from point 1 above.
With the module enabled, both the Vial GUI and the DFU bootloader are
reachable without root, flashing included; see
[flashing.md](flashing.md#permissions).

## Configuring keys with Vial

Two ways to reach the board, both live over the raw HID channel documented in
[identification.md](identification.md):

- The `vial` GUI (nixpkgs `vial`, 0.7.5; installed by the NixOS module
  above).
- The WebHID app at <https://vial.rocks>, no install required (Chromium-based
  browsers only, since WebHID is not implemented elsewhere).

Vial serves its own layout definition live over the protocol on connect,
keyed by the board's `VIAL_KEYBOARD_UID`; there is no JSON file to sideload.
That workflow (loading a per-board JSON definition by hand) is VIA's, not
Vial's. Once either app opens the board, remapping is: select a key on the
rendered layout, pick its new keycode from the picker, and the change applies
immediately and persists in the MCU's EEPROM, no reflash needed.

## The Esc+Enter unlock combo

Vial gates protected features (tap dance and macro editing, per this
keymap's `VIAL_TAP_DANCE_ENTRIES = 4` and `TAP_DANCE_ENABLE = yes`) behind a
physical unlock combo: hold both combo keys together when the app prompts for
an unlock.

For this keymap the combo is **Esc and Enter**. Derivation, reproducible from
the source in [identification.md](identification.md#upstream-source-of-this-firmware):

- `config.h` defines `VIAL_UNLOCK_COMBO_ROWS { 1, 4 }` and
  `VIAL_UNLOCK_COMBO_COLS { 3, 14 }`, i.e. the combo is matrix positions
  `(row 1, col 3)` and `(row 4, col 14)`.
- QMK's `fc660c` readme publishes the board's key matrix table directly. Row
  1 reads `1 2 3 Esc 4 7 5 6 9 0 - 8 =  BSpc Ins` across columns `0`-`F`, so
  column 3 is `Esc`. Row 4 reads `A S D Caps F J G H L ; ' K   Entr `, so
  column 14 is `Entr`.
- `vial.json`'s own visual layout corroborates this independently: of every
  key it renders, exactly two carry a distinct highlight color (`#777777`
  instead of the default `#cccccc`/`#aaaaaa`), and those two are matrix
  positions `1,3` and `4,14`, the same pair named in `config.h`.

Both matrix-table lookup and the highlighted keys in Vial's own layout file
agree: the unlock combo is Esc and Enter.

## Actuation point

Not adjustable at runtime, through Vial or otherwise. It is a compile-time
constant, `ACTUATION_DEPTH_ADJUSTMENT`, commented out (implicit 0) in this
keymap's `config.h`:

```c
// higher value means deeper actuation point, less sensitive
// be careful and only make small adjustments (steps of 1 or 2).
// too high and keys will fail to actuate. too low and keys will actuate spontaneously.
// test all keys before further adjustment.
// this should probably stay in the range +/-5.
// #define ACTUATION_DEPTH_ADJUSTMENT 0
```

The board carries an Analog Devices AD5258 digipot, reachable over I2C, that
can hardware-adjust the actuation point; the keyboard-level `rules.mk` even
compiles in an I2C driver for it (`I2C_DRIVER_REQUIRED = yes`,
`CUSTOM_MATRIX = yes`, `SRC += matrix.c ad5258.c`). Firmware deliberately
does not expose runtime control of it. QMK's readme is direct about why:

> Controller can operate AD5258 via I2C to change actuation point of keys.
> This may make keyboard unusable accidentally and it will be difficult to
> recovery in some situation. For safety firmware doesn't support it at this
> point, though.
>
> Lower value of RDAC register causes shallower actuation point.

**A common misreading to avoid:** the same readme also says "Functionality
for writing to the EEPROM has deliberately not been included to reduce the
chance of people messing up their boards." Several third-party guides read
this as "this controller's EEPROM is unreliable" and extend that worry to
Vial's saved keymaps. It is not about the MCU. It refers specifically to the
**AD5258 digipot's own EEPROM**, which stores the actuation calibration, not
the ATmega32U4's internal EEPROM. Vial's dynamic keymap and tap-dance storage
lives in the MCU's own EEPROM and works correctly on this controller, as
demonstrated by the board in day-to-day use: remaps made through Vial persist
across power cycles.

The only way to change the actuation point is to edit
`ACTUATION_DEPTH_ADJUSTMENT` in the keymap's `config.h`, rebuild, and reflash
(see [flashing.md](flashing.md)). Change it in steps of 1 or 2, stay within
roughly +/-5, and test every key after each change, per the guidance quoted
above.
