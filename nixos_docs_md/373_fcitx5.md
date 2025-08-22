## Fcitx5

Fcitx5 is an input method framework with extension support. It has three built-in Input Method Engine, Pinyin, QuWei and Table-based input methods.

The following snippet can be used to configure Fcitx:

```programlisting
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-hangul
      fcitx5-m17n
    ];
  };
}
```

`i18n.inputMethod.fcitx5.addons` is optional and can be used to add extra Fcitx5 addons.

Available extra Fcitx5 addons are:

- Anthy (`fcitx5-anthy`): Anthy is a system for Japanese input method. It converts Hiragana text to Kana Kanji mixed text.

- Chewing (`fcitx5-chewing`): Chewing is an intelligent Zhuyin input method. It is one of the most popular input methods among Traditional Chinese Unix users.

- Hangul (`fcitx5-hangul`): Korean input method.

- Unikey (`fcitx5-unikey`): Vietnamese input method.

- m17n (`fcitx5-m17n`): m17n is an input method that uses input methods and corresponding icons in the m17n database.

- mozc (`fcitx5-mozc`): A Japanese input method from Google.

- table-others (`fcitx5-table-other`): Various table-based input methods.

- chinese-addons (`fcitx5-chinese-addons`): Various chinese input methods.

- rime (`fcitx5-rime`): RIME support for fcitx5.
