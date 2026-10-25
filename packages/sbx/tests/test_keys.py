# Copyright (c) 2026 Bad3r
"""Key names and text against the Linux keycodes of a US layout."""

import string
import unittest

from sbx import keys


class KeysTest(unittest.TestCase):
    """Chords parse by name; text maps one chord per character."""

    def test_chords(self) -> None:
        """Names are case-insensitive and keep their order within a chord."""
        self.assertEqual(keys.chord("ctrl+shift+esc"), [29, 42, 1])
        self.assertEqual(keys.chord("F12"), [88])
        self.assertEqual(keys.chord("super+l"), [125, 38])
        self.assertEqual(keys.chord("ctrl+/"), [29, 53])
        for spec in ("", "ctrl+", "hyper", "+".join(["a"] * 17)):
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                keys.chord(spec)

    def test_printable_ascii(self) -> None:
        """Every printable character but CR, VT, and FF types, shifted ones with shift."""
        typable = [c for c in string.printable if c not in "\r\x0b\x0c"]
        chords = keys.text_chords("".join(typable))
        self.assertEqual(len(chords), len(typable))
        for character, chord in zip(typable, chords, strict=True):
            shifted = character in string.ascii_uppercase or character in '!@#$%^&*()_+{}:"~|<>?'
            with self.subTest(character=character):
                self.assertEqual(len(chord), 2 if shifted else 1)
                self.assertEqual(chord[0] == keys.SHIFT, shifted)
        self.assertEqual(keys.text_chords("aA"), [[30], [42, 30]])
        self.assertEqual(keys.text_chords("|"), [[42, 43]])

    def test_untypable(self) -> None:
        """Characters outside the layout fail before any chord is returned."""
        for text in ("é", "a\rb", "\x00"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                keys.text_chords(text)


if __name__ == "__main__":
    unittest.main()
