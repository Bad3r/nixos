## VA-API

[VA-API (Video Acceleration API)](https://www.intel.com/content/www/us/en/developer/articles/technical/linuxmedia-vaapi.html) is an open-source library and API specification, which provides access to graphics hardware acceleration capabilities for video processing.

VA-API drivers are loaded by `libva`. The version in nixpkgs is built to search the opengl driver path, so drivers can be installed in [`hardware.graphics.extraPackages`](options.html#opt-hardware.graphics.extraPackages).

VA-API can be tested using:

```programlisting
$ nix-shell -p libva-utils --run vainfo
```

### Intel

Modern Intel GPUs use the iHD driver, which can be installed with:

```programlisting
{ hardware.graphics.extraPackages = [ intel-media-driver ]; }
```

Older Intel GPUs use the i965 driver, which can be installed with:

```programlisting
{ hardware.graphics.extraPackages = [ intel-vaapi-driver ]; }
```
