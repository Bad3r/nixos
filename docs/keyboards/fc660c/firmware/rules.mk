# Reference copy. Goes to keyboards/fc660c/keymaps/vial-gaming/rules.mk in a
# vial-qmk checkout. Identical to the upstream vial keymap except for the last
# two lines, which free 3886 bytes together.

VIA_ENABLE = yes
VIAL_ENABLE = yes
LTO_ENABLE = yes
QMK_SETTINGS = no
CONSOLE_ENABLE = no
EXTRALDFLAGS = -Wl,--relax
REPEAT_KEY_ENABLE = no

# Tap dance also adds a tapping-term delay to every key it is bound to.
TAP_DANCE_ENABLE = no
MOUSEKEY_ENABLE = no
