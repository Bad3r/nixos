## Hardware

The digitalbitbox hardware package enables the udev rules for Digital Bitbox devices and may be installed as follows:

```programlisting
{ hardware.digitalbitbox.enable = true; }
```

In order to alter the udev rules, one may provide different values for the `udevRule51` and `udevRule52` attributes by means of overriding as follows:

```programlisting
{
  programs.digitalbitbox = {
    enable = true;
    package = pkgs.digitalbitbox.override { udevRule51 = "something else"; };
  };
}
```
