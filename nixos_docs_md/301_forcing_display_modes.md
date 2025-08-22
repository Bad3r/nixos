## Forcing display modes

In case of very wrong monitor controller and/or video driver combination you can [force the display to be enabled](https://mjmwired.net/kernel/Documentation/fb/modedb.txt#41) and skip some driver-side checks by adding `video=<OUTPUT>:e` to `boot.kernelParams`. This is exactly the case with [`amdgpu` drivers](https://gitlab.freedesktop.org/drm/amd/-/issues/615#note_1987392)

```programlisting
{
  # force enabled output to skip `amdgpu` checks

  hardware.display.outputs."DP-1".mode = "e";
  # completely disable output no matter what is connected to it

  hardware.display.outputs."VGA-2".mode = "d";

  /*
    equals
    boot.kernelParams = [ "video=DP-1:e" "video=VGA-2:d" ];
  */
}
```
