# Remapping the FC660C with Vial

Vial remaps the board live over the raw HID channel described in [identification-hid.md](identification-hid.md), from either of two apps:

- The `vial` GUI, installed by the `vial` app row that the [NixOS module](configuration.md#nixos-module) turns on.
- The WebHID app at <https://vial.rocks>, with no install, in Chromium-based browsers only, since WebHID is not implemented elsewhere.

## Configuring keys

Vial serves its own layout definition over the protocol on connect, keyed by the board's `VIAL_KEYBOARD_UID`, so there is no Vial definition file to sideload.
Loading a per-board JSON definition by hand is VIA's workflow, not Vial's.

Once either app opens the board, select a key on the rendered layout and pick its new keycode from the picker.
The change applies immediately and persists in the MCU's EEPROM, with no reflash.

The checked-in [layout.vil](layout.vil) is a snapshot of the dynamic keymap, restored through Vial's **Load saved layout** action.
Neither NixOS nor the firmware build consumes it, so it goes stale unless it is re-exported after remaps.

Tap dance is compiled out by `TAP_DANCE_ENABLE = no` in [firmware/rules.mk](firmware/rules.mk), so the snapshot's `tap_dance` array is empty.
Vial's feature guards expose zero tap-dance entries on this board, even though the inherited `VIAL_TAP_DANCE_ENTRIES = 4` definition remains in [firmware/config.h](firmware/config.h).

## The Esc+Enter unlock combo

Vial gates protected features, macro editing included, behind a physical unlock combo: hold both combo keys together when the app prompts for an unlock.
For this keymap the combo is **Esc and Enter**, reproducible from the upstream source in [identification.md](identification.md#upstream-source-and-local-overlay):

- The upstream `config.h` defines `VIAL_UNLOCK_COMBO_ROWS { 1, 4 }` and `VIAL_UNLOCK_COMBO_COLS { 3, 14 }`, matrix positions `(row 1, col 3)` and `(row 4, col 14)`.
- The key matrix table in QMK's `fc660c` readme puts `Esc` at row 1, column 3, and `Entr` at row 4, column 14.
- The upstream `vial.json` agrees independently: exactly two of its rendered keys carry the highlight color `#777777` instead of the default `#cccccc` or `#aaaaaa`.
  They sit at matrix positions `1,3` and `4,14`.

## Actuation point

The actuation point is not adjustable at runtime, through Vial or otherwise: it is the compile-time constant `ACTUATION_DEPTH_ADJUSTMENT`.
The upstream `vial` keymap leaves it undefined, an effective offset of 0, while the `vial-gaming` overlay flashed on this board sets it in [firmware/config.h](firmware/config.h).

The board carries an Analog Devices AD5258 digipot on I2C that can hardware-adjust the actuation point, and the keyboard-level `rules.mk` compiles in its driver (`I2C_DRIVER_REQUIRED = yes`, `CUSTOM_MATRIX = yes`, `SRC += matrix.c ad5258.c`).
The firmware deliberately exposes no runtime control of it, because QMK's readme warns that operating the digipot can make the keyboard unusable and hard to recover.
A lower RDAC register value gives a shallower actuation point.

The same readme leaves out EEPROM writing to reduce the chance of breaking a board.
Several third-party guides misread that as an unreliable controller EEPROM and extend the worry to Vial's saved keymaps.
It refers to the AD5258 digipot's own EEPROM, which stores the actuation calibration, not to the ATmega32U4's internal EEPROM.
Vial's dynamic keymap lives in the MCU's own EEPROM and works on this controller: remaps made through Vial persist across power cycles.

Changing the actuation point means editing `ACTUATION_DEPTH_ADJUSTMENT` in the keymap's `config.h`, rebuilding, and reflashing (see [flashing.md](flashing.md)).
Change it in steps of 1 or 2; [firmware/](firmware/README.md#why-each-override) gives the safe range and how the offset applies at boot.

QMK fc660c readme: <https://github.com/qmk/qmk_firmware/tree/master/keyboards/fc660c>
