## Xfce Desktop Environment

**Table of Contents**

[Thunar](#sec-xfce-thunar-plugins)

[Troubleshooting](#sec-xfce-troubleshooting)

To enable the Xfce Desktop Environment, set

```programlisting
{
  services.xserver.desktopManager.xfce.enable = true;
  services.displayManager.defaultSession = "xfce";
}
```

Optionally, _picom_ can be enabled for nice graphical effects, some example settings:

```programlisting
{
  services.picom = {
    enable = true;
    fade = true;
    inactiveOpacity = 0.9;
    shadow = true;
    fadeDelta = 4;
  };
}
```

Some Xfce programs are not installed automatically. To install them manually (system wide), put them into your [`environment.systemPackages`](options.html#opt-environment.systemPackages) from `pkgs.xfce`.
