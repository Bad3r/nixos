## Using XFree86 Modeline definitions

`hardware.display.edid.modelines` utilizes `pkgs.edid-generator` package allowing you to conveniently use [`XFree86 Modeline`](https://en.wikipedia.org/wiki/XFree86_Modeline) entries as EDID binaries:

```programlisting
{
  hardware.display.edid.modelines."PG278Q_60" =
    "    241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync";
  hardware.display.edid.modelines."PG278Q_120" =
    "   497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync";

  /*
    equals:
    hardware.display.edid.packages = [
      (pkgs.edid-generator.overrideAttrs {
        clean = true;
        modelines = ''
          Modeline "PG278Q_60"      241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync
          Modeline "PG278Q_120"     497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync
        '';
      })
    ];
  */
}
```
