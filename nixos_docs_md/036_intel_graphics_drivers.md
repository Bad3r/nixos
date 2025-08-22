## Intel Graphics drivers

The default and recommended driver for Intel Graphics in X.org is `modesetting` (included in the xorg-server package itself). This is a generic driver which uses the kernel [mode setting](https://en.wikipedia.org/wiki/Mode_setting) (KMS) mechanism, it supports Glamor (2D graphics acceleration via OpenGL) and is actively maintained, it may perform worse in some cases (like in old chipsets).

There is a second driver, `intel` (provided by the xf86-video-intel package), specific to older Intel iGPUs from generation 2 to 9. It is not recommended by most distributions: it lacks several modern features (for example, it doesn’t support Glamor) and the package hasn’t been officially updated since 2015.

Third generation and older iGPUs (15-20+ years old) are not supported by the `modesetting` driver (X will crash upon startup). Thus, the `intel` driver is required for these chipsets. Otherwise, the results vary depending on the hardware, so you may have to try both drivers. Use the option [`services.xserver.videoDrivers`](options.html#opt-services.xserver.videoDrivers) to set one. The recommended configuration for modern systems is:

```programlisting
{ services.xserver.videoDrivers = [ "modesetting" ]; }
```

### Note

The `modesetting` driver doesn’t currently provide a `TearFree` option (this will become available in an upcoming X.org release), So, without using a compositor (for example, see [`services.picom.enable`](options.html#opt-services.picom.enable)) you will experience screen tearing.

If you experience screen tearing no matter what, this configuration was reported to resolve the issue:

```programlisting
{
  services.xserver.videoDrivers = [ "intel" ];
  services.xserver.deviceSection = ''
    Option "DRI" "2"
    Option "TearFree" "true"
  '';
}
```

Note that this will likely downgrade the performance compared to `modesetting` or `intel` with DRI 3 (default).
