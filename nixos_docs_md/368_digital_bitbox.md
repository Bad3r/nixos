## Digital Bitbox

**Table of Contents**

[Package](#sec-digitalbitbox-package)

[Hardware](#sec-digitalbitbox-hardware-module)

Digital Bitbox is a hardware wallet and second-factor authenticator.

The `digitalbitbox` programs module may be installed by setting `programs.digitalbitbox` to `true` in a manner similar to

```programlisting
{ programs.digitalbitbox.enable = true; }
```

and bundles the `digitalbitbox` package (see [the section called “Package”](#sec-digitalbitbox-package "Package")), which contains the `dbb-app` and `dbb-cli` binaries, along with the hardware module (see [the section called “Hardware”](#sec-digitalbitbox-hardware-module "Hardware")) which sets up the necessary udev rules to access the device.

Enabling the digitalbitbox module is pretty much the easiest way to get a Digital Bitbox device working on your system.

For more information, see [https://digitalbitbox.com/start_linux](https://digitalbitbox.com/start_linux).
