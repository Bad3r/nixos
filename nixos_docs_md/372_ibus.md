## IBus

IBus is an Intelligent Input Bus. It provides full featured and user friendly input method user interface.

The following snippet can be used to configure IBus:

```programlisting
{
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [
      anthy
      hangul
      mozc
    ];
  };
}
```

`i18n.inputMethod.ibus.engines` is optional and can be used to add extra IBus engines.

Available extra IBus engines are:

- Anthy (`ibus-engines.anthy`): Anthy is a system for Japanese input method. It converts Hiragana text to Kana Kanji mixed text.

- Hangul (`ibus-engines.hangul`): Korean input method.

- libpinyin (`ibus-engines.libpinyin`): A Chinese input method.

- m17n (`ibus-engines.m17n`): m17n is an input method that uses input methods and corresponding icons in the m17n database.

- mozc (`ibus-engines.mozc`): A Japanese input method from Google.

- Table (`ibus-engines.table`): An input method that load tables of input methods.

- table-others (`ibus-engines.table-others`): Various table-based input methods. To use this, and any other table-based input methods, it must appear in the list of engines along with `table`. For example:

  ```programlisting
  {
    ibus.engines = with pkgs.ibus-engines; [
      table
      table-others
    ];
  }
  ```

To use any input method, the package must be added in the configuration, as shown above, and also (after running `nixos-rebuild`) the input method must be added from IBus’ preference dialog.

### Troubleshooting

If IBus works in some applications but not others, a likely cause of this is that IBus is depending on a different version of `glib` to what the applications are depending on. This can be checked by running `nix-store -q --requisites <path> | grep glib`, where `<path>` is the path of either IBus or an application in the Nix store. The `glib` packages must match exactly. If they do not, uninstalling and reinstalling the application is a likely fix.
