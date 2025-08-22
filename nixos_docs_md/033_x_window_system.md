## X Window System

**Table of Contents**

[Auto-login](#sec-x11-auto-login)

[Running X without a display manager](#sec-x11-startx)

[Intel Graphics drivers](#sec-x11--graphics-cards-intel)

[Proprietary NVIDIA drivers](#sec-x11-graphics-cards-nvidia)

[Touchpads](#sec-x11-touchpads)

[GTK/Qt themes](#sec-x11-gtk-and-qt-themes)

[Custom XKB layouts](#custom-xkb-layouts)

The X Window System (X11) provides the basis of NixOS’ graphical user interface. It can be enabled as follows:

```programlisting
{ services.xserver.enable = true; }
```

The X server will automatically detect and use the appropriate video driver from a set of X.org drivers (such as `vesa` and `intel`). You can also specify a driver manually, e.g.

```programlisting
{ services.xserver.videoDrivers = [ "r128" ]; }
```

to enable X.org’s `xf86-video-r128` driver.

You also need to enable at least one desktop or window manager. Otherwise, you can only log into a plain undecorated `xterm` window. Thus you should pick one or more of the following lines:

```programlisting
{
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.desktopManager.mate.enable = true;
  services.xserver.windowManager.xmonad.enable = true;
  services.xserver.windowManager.twm.enable = true;
  services.xserver.windowManager.icewm.enable = true;
  services.xserver.windowManager.i3.enable = true;
  services.xserver.windowManager.herbstluftwm.enable = true;
}
```

NixOS’s default _display manager_ (the program that provides a graphical login prompt and manages the X server) is LightDM. You can select an alternative one by picking one of the following lines:

```programlisting
{
  services.displayManager.sddm.enable = true;
  services.displayManager.gdm.enable = true;
}
```

You can set the keyboard layout (and optionally the layout variant):

```programlisting
{
  services.xserver.xkb.layout = "de";
  services.xserver.xkb.variant = "neo";
}
```

The X server is started automatically at boot time. If you don’t want this to happen, you can set:

```programlisting
{ services.xserver.autorun = false; }
```

The X server can then be started manually:

```programlisting

# systemctl start display-manager.service

```

On 64-bit systems, if you want OpenGL for 32-bit programs such as in Wine, you should also set the following:

```programlisting
{ hardware.graphics.enable32Bit = true; }
```
