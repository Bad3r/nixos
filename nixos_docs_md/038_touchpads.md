## Touchpads

Support for Synaptics touchpads (found in many laptops such as the Dell Latitude series) can be enabled as follows:

```programlisting
{ services.libinput.enable = true; }
```

The driver has many options (see [Appendix A](options.html "Appendix A. Configuration Options")). For instance, the following disables tap-to-click behavior:

```programlisting
{ services.libinput.touchpad.tapping = false; }
```

Note: the use of `services.xserver.synaptics` is deprecated since NixOS 17.09.
