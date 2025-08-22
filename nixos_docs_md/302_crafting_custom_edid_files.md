## Crafting custom EDID files

To make custom EDID binaries discoverable you should first create a derivation storing them at `$out/lib/firmware/edid/` and secondly add that derivation to `hardware.display.edid.packages` NixOS option:

```programlisting
{
  hardware.display.edid.packages = [
    (pkgs.runCommand "edid-custom" { } ''
      mkdir -p $out/lib/firmware/edid
      base64 -d > "$out/lib/firmware/edid/custom1.bin" <<'EOF'
      <insert your base64 encoded EDID file here `base64 < /sys/class/drm/card0-.../edid`>
      EOF
      base64 -d > "$out/lib/firmware/edid/custom2.bin" <<'EOF'
      <insert your base64 encoded EDID file here `base64 < /sys/class/drm/card1-.../edid`>
      EOF
    '')
  ];
}
```

There are 2 options significantly easing preparation of EDID files:

- `hardware.display.edid.linuxhw`

- `hardware.display.edid.modelines`
