# Building FC660C firmware on NixOS

`vial-qmk` has no `shell.nix` or `flake.nix`, and two of its assumptions do not
hold on a current NixOS host. This directory carries a working build recipe and
the keymap overlay that was actually flashed, so a rebuild does not have to
rediscover either.

Files here are reference copies, not built by this repo. They are meant to be
dropped into a `vial-qmk` checkout.

| File                               | Goes to                                         |
| ---------------------------------- | ----------------------------------------------- |
| [config.h](config.h)               | `keyboards/fc660c/keymaps/vial-gaming/config.h` |
| [rules.mk](rules.mk)               | `keyboards/fc660c/keymaps/vial-gaming/rules.mk` |
| [flash-fc660c.sh](flash-fc660c.sh) | anywhere; takes a `.hex` path argument          |

## Two things that break the obvious build

**The bundled Python does not run on 3.12 or newer.** `lib/python/qmk/math.py`
calls `ast.Num`, removed in Python 3.12, while nixpkgs' `qmk` package runs on
3.14. `make` fails with `AttributeError: module 'ast' has no attribute 'Num'`
before compiling anything. Install the CLI under an older interpreter instead:

```sh
uv tool install --python 3.11 qmk
```

**The AVR libc attribute is cross-scoped.** `nixpkgs#avrlibc` is marked
unsupported on `x86_64-linux` and aborts evaluation. Use
`pkgsCross.avr.avrlibc`, whose `pkgsCross.avr.buildPackages.gcc` counterpart
provides `avr-gcc`.

## Build

```sh
git clone --depth 1 --branch vial https://github.com/vial-kb/vial-qmk
cd vial-qmk
git submodule update --init --depth 1 lib/lufa

# The overlay is only config.h and rules.mk; the rest of the keymap comes from
# upstream, so start from a copy of it rather than an empty directory.
cp -r keyboards/fc660c/keymaps/{vial,vial-gaming}
cp <this-dir>/config.h <this-dir>/rules.mk keyboards/fc660c/keymaps/vial-gaming/

nix shell nixpkgs#gnumake nixpkgs#git \
  nixpkgs#pkgsCross.avr.avrlibc \
  nixpkgs#pkgsCross.avr.buildPackages.gcc \
  nixpkgs#pkgsCross.avr.buildPackages.binutils \
  -c bash -c 'export PATH="$HOME/.local/bin:$PATH"; make fc660c:vial-gaming'
```

The `PATH` export must be single-quoted so it expands inside the `nix shell`.
Expanding it outside replaces the shell's own `PATH` and `avr-gcc` disappears.

Output lands at `fc660c_vial-gaming.hex` in the checkout root. Flash it with
[flash-fc660c.sh](flash-fc660c.sh); see [../flashing.md](../flashing.md) for
bootloader entry and recovery.

Builds are not byte-reproducible. QMK generates a `version.h` carrying
`QMK_BUILDDATE` and a derived `BUILD_ID`, so two builds of identical sources
minutes apart differ in `sha256`. Compare the reported firmware size and the
`-D...ENABLE` set in `.build/obj_fc660c_vial-gaming/cflags.txt` instead. This
overlay builds to 24130/28672 bytes.

## The flash budget is the binding constraint

The ATmega32U4 leaves 28672 bytes after the DFU bootloader. Measured sizes,
all with `LTO_ENABLE = yes`:

| Configuration                              | Size        | Result          |
| ------------------------------------------ | ----------- | --------------- |
| Upstream `vial` keymap                     | 26612 (92%) | fits            |
| plus `QMK_SETTINGS`                        | 32206       | 3534 over       |
| plus `QMK_SETTINGS`, no tap dance          | 30496       | 1824 over       |
| plus `QMK_SETTINGS`, no mouse keys         | 30032       | 1360 over       |
| plus `QMK_SETTINGS`, neither               | 28320 (98%) | fits, 352 free  |
| plus `ACTUATION_DEPTH_ADJUSTMENT`          | 27562 (96%) | fits, 1110 free |
| plus `QMK_SETTINGS` and actuation, neither | 29294       | 622 over        |
| `vial-gaming` (this overlay)               | 24130 (84%) | fits, 4542 free |

The practical consequence: the Vial GUI's QMK Settings tab and
`ACTUATION_DEPTH_ADJUSTMENT` cannot coexist on this MCU. Upstream disabled
`QMK_SETTINGS` for this board in commit `e6dee240` (2025-06-22), titled
"mass disable qmk settings on too big keyboards", which is why a board flashed
from current upstream loses the tab that older builds had.

## Why each override

`ACTUATION_DEPTH_ADJUSTMENT -2` sets the Topre actuation point shallower. On
boot `adjust_actuation_point()` reads the AD5258 digipot's factory EEPROM
calibration, applies the offset, clamps to 0..63, and writes the volatile RDAC
register. It never writes the digipot's EEPROM, so the factory calibration
survives and recovery is always a reflash. Keep within roughly +/-5: too low and
keys actuate spontaneously, too high and they fail to actuate. Test every key
after changing it.

`FORCE_NKRO` is the override that actually works. `NKRO_DEFAULT_ON` alone is
insufficient: it is read only inside `eeconfig_init_quantum()`, so a flash that
preserves the existing EEPROM never applies it and a stale `nkro=false` wins.
`FORCE_NKRO` sets `keymap_config.nkro = 1` and rewrites eeconfig on every boot
(`quantum/keyboard.c`). Upstream marks it deprecated, which costs a
compile-time `#pragma message` and nothing else. With it set, do not bind
`NK_TOGG`: toggling turns NKRO off until the next boot.

`TAP_DANCE_ENABLE = no` and `MOUSEKEY_ENABLE = no` free 3886 bytes together.
Tap dance also adds latency to any key it is bound to, since the firmware must
wait out a tapping term before resolving the tap count.

## What this board cannot do

Rapid trigger, per-key actuation, and SOCD cleaning are impossible here. The
controller thresholds capacitance through a comparator against a single global
reference set by the digipot, so there is no continuous per-key position data to
build them on. One global actuation point is the ceiling.

Polling is already 1000 Hz (`bInterval 1` on every endpoint). Debounce tuning
does not apply either: `keyboards/fc660c/matrix.c` implements a custom Topre
capacitive scan with hardware timing and never uses QMK's debounce framework,
so there is no `DEBOUNCE` value to lower.
