/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Reference copy. Goes to keyboards/fc660c/keymaps/vial-gaming/config.h in a
   vial-qmk checkout. The first four defines are unchanged from the upstream
   vial keymap; everything below them is the overlay. */

#pragma once

#define VIAL_KEYBOARD_UID {0x86, 0xDA, 0x85, 0x0E, 0x54, 0x70, 0xA0, 0xA2}
#define VIAL_UNLOCK_COMBO_ROWS { 1, 4 }
#define VIAL_UNLOCK_COMBO_COLS { 3, 14 }
#define VIAL_TAP_DANCE_ENTRIES 4

/* Shallower Topre actuation: RDAC = factory calibration - 2. Stay within +/-5. */
#define ACTUATION_DEPTH_ADJUSTMENT -2

/* Read only by eeconfig_init_quantum(), so a flash that keeps the existing
   EEPROM never applies it. Kept for a board whose EEPROM does get reset. */
#define NKRO_DEFAULT_ON true

/* The override that actually takes: sets keymap_config.nkro every boot
   regardless of stored eeconfig. Do not bind NK_TOGG alongside it. */
#define FORCE_NKRO
