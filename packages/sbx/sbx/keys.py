# Copyright (c) 2026 Bad3r
"""Key names and text as Linux input keycodes on a US layout, for virDomainSendKey.

Both parsers raise ValueError, which `gui` reports as invalid-argument.
"""

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence

# virDomainSendKey takes at most this many keys in one chord.
MAX_CHORD = 16
# Each chord waits for QEMU's queue, and `key` journals them all.
MAX_CHORDS = 64
MAX_POSITIONS = 10
SHIFT = 42

_LETTERS = dict(
    zip(
        "qwertyuiopasdfghjklzxcvbnm",
        [*range(16, 26), *range(30, 39), *range(44, 51)],
        strict=True,
    )
)
_DIGITS = dict(zip("1234567890", range(2, 12), strict=True))
_PUNCTUATION = {
    "-": 12,
    "=": 13,
    "[": 26,
    "]": 27,
    ";": 39,
    "'": 40,
    "`": 41,
    "\\": 43,
    ",": 51,
    ".": 52,
    "/": 53,
}
_SHIFTED = dict(
    zip(
        '!@#$%^&*()_+{}:"~|<>?',
        "1234567890-=[];'`\\,./",
        strict=True,
    )
)
_NAMED = {
    "esc": 1,
    "backspace": 14,
    "tab": 15,
    "enter": 28,
    "ctrl": 29,
    "shift": SHIFT,
    "alt": 56,
    "space": 57,
    "capslock": 58,
    **{f"f{number}": 58 + number for number in range(1, 11)},
    "f11": 87,
    "f12": 88,
    "rctrl": 97,
    "print": 99,
    "altgr": 100,
    "home": 102,
    "up": 103,
    "pageup": 104,
    "left": 105,
    "right": 106,
    "end": 107,
    "down": 108,
    "pagedown": 109,
    "insert": 110,
    "delete": 111,
    "super": 125,
    "menu": 127,
}
KEYS = {**_LETTERS, **_DIGITS, **_PUNCTUATION, **_NAMED}
ALIASES = {
    "return": "enter",
    "escape": "esc",
    "del": "delete",
    "ins": "insert",
    "pgup": "pageup",
    "page_up": "pageup",
    "pgdn": "pagedown",
    "page_down": "pagedown",
    "control": "ctrl",
    "win": "super",
    "meta": "super",
    "cmd": "super",
    "option": "alt",
    "bksp": "backspace",
    "prtsc": "print",
}
_TEXT = {
    **{character: [code] for character, code in KEYS.items() if len(character) == 1},
    **{character.upper(): [SHIFT, code] for character, code in _LETTERS.items()},
    **{character: [SHIFT, KEYS[base]] for character, base in _SHIFTED.items()},
    " ": [KEYS["space"]],
    "\n": [KEYS["enter"]],
    "\t": [KEYS["tab"]],
}


def chord(spec: str) -> list[int]:
    """Parse `ctrl+alt+t` into the keycodes pressed together, in order."""
    names = spec.lower().split("+")
    if len(names) > MAX_CHORD:
        msg = f"'{spec}' presses more than {MAX_CHORD} keys"
        raise ValueError(msg)
    names = [ALIASES.get(name, name) for name in names]
    unknown = [name for name in names if name not in KEYS]
    if unknown:
        aliases = ", ".join(f"{alias}={name}" for alias, name in ALIASES.items())
        msg = (
            f"'{spec}' names unknown keys {', '.join(map(repr, unknown))}; keys are a-z, 0-9, "
            f"{' '.join(_PUNCTUATION)}, and {', '.join(_NAMED)}; aliases: {aliases}"
        )
        raise ValueError(msg)
    return [KEYS[name] for name in names]


def positions(indices: Sequence[int]) -> str:
    """Name where characters sit in a text without naming them, which may be a secret."""
    shown = ", ".join(str(index + 1) for index in indices[:MAX_POSITIONS])
    more = f" and {len(indices) - MAX_POSITIONS} more" if len(indices) > MAX_POSITIONS else ""
    return f"{len(indices)} characters, at positions {shown}{more}"


def text_chords(text: str) -> list[list[int]]:
    """Translate text into one chord per character, refusing what a US layout cannot type."""
    untypable = [index for index, character in enumerate(text) if character not in _TEXT]
    if untypable:
        msg = f"no US-layout key types {positions(untypable)}"
        raise ValueError(msg)
    return [_TEXT[character] for character in text]
