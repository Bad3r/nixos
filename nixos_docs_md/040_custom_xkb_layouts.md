## Custom XKB layouts

It is possible to install custom [XKB](https://en.wikipedia.org/wiki/X_keyboard_extension) keyboard layouts using the option `services.xserver.xkb.extraLayouts`.

As a first example, we are going to create a layout based on the basic US layout, with an additional layer to type some greek symbols by pressing the right-alt key.

Create a file called `us-greek` with the following content (under a directory called `symbols`; it’s an XKB peculiarity that will help with testing):

```programlisting
xkb_symbols "us-greek"
{
  include "us(basic)"            // includes the base US keys
  include "level3(ralt_switch)"  // configures right alt as a third level switch

  key <LatA> { [ a, A, Greek_alpha ] };
  key <LatB> { [ b, B, Greek_beta  ] };
  key <LatG> { [ g, G, Greek_gamma ] };
  key <LatD> { [ d, D, Greek_delta ] };
  key <LatZ> { [ z, Z, Greek_zeta  ] };
};
```

A minimal layout specification must include the following:

```programlisting
{
  services.xserver.xkb.extraLayouts.us-greek = {
    description = "US layout with alt-gr greek";
    languages = [ "eng" ];
    symbolsFile = /yourpath/symbols/us-greek;
  };
}
```

### Note

The name (after `extraLayouts.`) should match the one given to the `xkb_symbols` block.

Applying this customization requires rebuilding several packages, and a broken XKB file can lead to the X session crashing at login. Therefore, you’re strongly advised to **test your layout before applying it**:

```programlisting
$ nix-shell -p xorg.xkbcomp
$ setxkbmap -I/yourpath us-greek -print | xkbcomp -I/yourpath - $DISPLAY
```

You can inspect the predefined XKB files for examples:

```programlisting
$ echo "$(nix-build --no-out-link '<nixpkgs>' -A xorg.xkeyboardconfig)/etc/X11/xkb/"
```

Once the configuration is applied, and you did a logout/login cycle, the layout should be ready to use. You can try it by e.g. running `setxkbmap us-greek` and then type `<alt>+a` (it may not get applied in your terminal straight away). To change the default, the usual `services.xserver.xkb.layout` option can still be used.

A layout can have several other components besides `xkb_symbols`, for example we will define new keycodes for some multimedia key and bind these to some symbol.

Use the _xev_ utility from `pkgs.xorg.xev` to find the codes of the keys of interest, then create a `media-key` file to hold the keycodes definitions

```programlisting
xkb_keycodes "media"
{
 <volUp>   = 123;
 <volDown> = 456;
}
```

Now use the newly define keycodes in `media-sym`:

```programlisting
xkb_symbols "media"
{
 key.type = "ONE_LEVEL";
 key <volUp>   { [ XF86AudioLowerVolume ] };
 key <volDown> { [ XF86AudioRaiseVolume ] };
}
```

As before, to install the layout do

```programlisting
{
  services.xserver.xkb.extraLayouts.media = {
    description = "Multimedia keys remapping";
    languages = [ "eng" ];
    symbolsFile = /path/to/media-key;
    keycodesFile = /path/to/media-sym;
  };
}
```

### Note

The function `pkgs.writeText <filename> <content>` can be useful if you prefer to keep the layout definitions inside the NixOS configuration.

Unfortunately, the Xorg server does not (currently) support setting a keymap directly but relies instead on XKB rules to select the matching components (keycodes, types, …) of a layout. This means that components other than symbols won’t be loaded by default. As a workaround, you can set the keymap using `setxkbmap` at the start of the session with:

```programlisting
{
  services.xserver.displayManager.sessionCommands = "setxkbmap -keycodes media";
}
```

If you are manually starting the X server, you should set the argument `-xkbdir /etc/X11/xkb`, otherwise X won’t find your layout files. For example with `xinit` run

```programlisting
$ xinit -- -xkbdir /etc/X11/xkb
```

To learn how to write layouts take a look at the XKB [documentation](https://www.x.org/releases/current/doc/xorg-docs/input/XKB-Enhancing.html#Defining_New_Layouts) . More example layouts can also be found [here](https://wiki.archlinux.org/index.php/X_KeyBoard_extension#Basic_examples) .
