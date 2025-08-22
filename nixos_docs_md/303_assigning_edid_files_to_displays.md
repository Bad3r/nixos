## Assigning EDID files to displays

To assign available custom EDID binaries to your monitor (video output) use `hardware.display.outputs."<NAME>".edid` option. Under the hood it adds `drm.edid_firmware` entry to `boot.kernelParams` NixOS option for each configured output:

```programlisting
{
  hardware.display.outputs."VGA-1".edid = "custom1.bin";
  hardware.display.outputs."VGA-2".edid = "custom2.bin";
  /*
    equals:
    boot.kernelParams = [ "drm.edid_firmware=VGA-1:edid/custom1.bin,VGA-2:edid/custom2.bin" ];
  */
}
```
