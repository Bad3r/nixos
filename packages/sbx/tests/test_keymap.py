# Copyright (c) 2026 Bad3r
"""Binding the characters a text needs outside the guest's X keymap before xdotool types."""

import unittest

from sbx import gui
from sbx.errors import SbxError

# xmodmap -pk's layout, with the rows of a US keymap that matter here.
HEADER = (
    b"There are 7 KeySyms per KeyCode; KeyCodes range from 8 to 255.\n"
    b"\n"
    b"    KeyCode\tKeysym (Keysym)\t...\n"
    b"    Value  \tValue   (Name) \t...\n"
    b"\n"
)
ROWS = (
    b"      8    \t\n"
    b"      9    \t0xff1b (Escape)\t0x0000 (NoSymbol)\t0xff1b (Escape)\t\n"
    b"     38    \t0x0061 (a)\t0x0041 (A)\t0x0061 (a)\t0x0041 (A)\t\n"
    b"     97    \t\n"
    b"    103    \t\n"
    b"    120    \t\n"
)
UNOWNED = b"_SBX_TYPE_KEYCODES:  no such atom on any window.\n"


def keymap(*rows: bytes, owned: bytes = UNOWNED) -> gui.Keymap:
    """Parse the US rows plus the given ones, with the owned-keycodes line given."""
    return gui.parse_keymap(HEADER + ROWS + b"".join(rows) + owned)


def row(keycode: int, *keysyms: int) -> bytes:
    """A row as xmodmap -pk prints it, the core keysyms repeated for the second group."""
    if len(keysyms) == 1:
        keysyms = (keysyms[0], 0)
    cells = "".join(f"{keysym:#06x} (U{keysym:X})\t" for keysym in (*keysyms, *keysyms))
    return f"    {keycode:3d}    \t{cells}\n".encode()


class ParseTest(unittest.TestCase):
    """The guest prints the keymap, so only well-formed output reads."""

    def test_reads(self) -> None:
        """Rows map keycodes to keysyms, and the property names the owned keycodes."""
        parsed = keymap(owned=b'_SBX_TYPE_KEYCODES = "97 103"\n')
        self.assertEqual(parsed.rows[8], ())
        self.assertEqual(parsed.rows[9], (0xFF1B, 0, 0xFF1B))
        self.assertEqual(parsed.rows[38], (0x61, 0x41, 0x61, 0x41))
        self.assertEqual(parsed.owned, (97, 103))
        self.assertEqual(keymap(owned=b'_SBX_TYPE_KEYCODES = "103 97 103"\n').owned, (103, 97))
        for line in (UNOWNED, b"_SBX_TYPE_KEYCODES:  not found.\n"):
            with self.subTest(line=line):
                self.assertEqual(keymap(owned=line).owned, ())

    def test_refuses(self) -> None:
        """No rows, no property line, or a keycode X cannot have fails as agent-reply."""
        cases = [
            HEADER + UNOWNED,
            HEADER + ROWS,
            HEADER + ROWS + b"    300    \t\n" + UNOWNED,
            HEADER + ROWS + b"     38    \t\n" + UNOWNED,
            HEADER + ROWS + b'_SBX_TYPE_KEYCODES = "7"\n',
            HEADER + ROWS + b'_SBX_TYPE_KEYCODES = "256"\n',
        ]
        for output in cases:
            with self.subTest(output=output), self.assertRaises(SbxError) as refused:
                gui.parse_keymap(output)
            self.assertEqual(refused.exception.code, "agent-reply")


class BindingsTest(unittest.TestCase):
    """Spare keycodes take what the keymap lacks, never the lowest empty one."""

    def test_layout_text_binds_nothing(self) -> None:
        """ASCII and characters the keymap holds need no binding."""
        self.assertEqual(gui.keymap_bindings("aA !\n", keymap()), {})
        bound = keymap(row(200, 0xE9, 0xC9), row(201, 0x1002713, 0x1002713))
        self.assertEqual(gui.keymap_bindings("éÉ✓", bound), {})

    def test_pairs(self) -> None:
        """An uppercase Latin-1 letter sits shifted, over its lowercase when the text has it."""
        self.assertEqual(
            gui.keymap_bindings("É✓é", keymap()),
            {97: (0xE9, 0xC9), 103: (0x1002713, 0x1002713)},
        )
        self.assertEqual(
            gui.keymap_bindings("Ü✓✔é", keymap()),
            {97: (0x1002713, 0xDC), 103: (0x1002714, 0xE9)},
        )
        # Multiplication sign is no letter, so xdotool holds no Shift for it.
        self.assertEqual(gui.keymap_bindings("\u00d7", keymap()), {97: (0xD7, 0xD7)})

    def test_shifted_needs_level_two(self) -> None:
        """An uppercase letter bound unshifted counts as missing, since xdotool adds Shift."""
        self.assertEqual(gui.keymap_bindings("É", keymap(row(200, 0xC9))), {97: (0xC9, 0xC9)})

    def test_reclaims_owned(self) -> None:
        """Owned keycodes the text does not use come after the empty ones; used ones stay."""
        owned = keymap(
            row(200, 0x1002713, 0x1002714),
            row(201, 0xE4, 0xE4),
            owned=b'_SBX_TYPE_KEYCODES = "200 201"\n',
        )
        text = "✓āĂăĄąĆ"
        self.assertEqual(
            gui.keymap_bindings(text, owned),
            {97: (0x1000101, 0x1000102), 103: (0x1000103, 0x1000104), 120: (0x1000105, 0x1000106)},
        )
        text += "ć"
        self.assertEqual(gui.keymap_bindings(text, owned)[201], (0x1000107, 0x1000107))

    def test_reclaims_oldest_sbx_rows(self) -> None:
        """Owned keycodes go oldest first, and never one holding a key sbx would not bind."""
        rows = (
            row(200, 0xE4, 0xE4),
            row(201, 0x1002713, 0x1002713),
            row(202, 0x61, 0x41),
            row(203, 0x1008FF11),
        )
        owned = keymap(*rows, owned=b'_SBX_TYPE_KEYCODES = "201 202 203 200"\n')
        text = "".join(chr(0x100 + index) for index in range(8))
        self.assertEqual(list(gui.keymap_bindings(text, owned)), [97, 103, 120, 201])
        with self.assertRaises(SbxError):
            gui.keymap_bindings(text + "\u0108\u0109\u010a", owned)

    def test_capacity(self) -> None:
        """More pairs than spare keycodes fail before any binding, naming no character."""
        text = "".join(chr(0x100 + index) for index in range(7))
        with self.assertRaises(SbxError) as refused:
            gui.keymap_bindings(text, keymap())
        self.assertEqual(refused.exception.code, "invalid-argument")
        self.assertIn("needs 4 spare keycodes", str(refused.exception))
        self.assertIn("3 are free", str(refused.exception))
        for character in text:
            self.assertNotIn(character, str(refused.exception))
        self.assertNotIn(8, gui.keymap_bindings(text[:6], keymap()))


if __name__ == "__main__":
    unittest.main()
