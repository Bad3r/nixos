## Proprietary NVIDIA drivers

NVIDIA provides a proprietary driver for its graphics cards that has better 3D performance than the X.org drivers. It is not enabled by default because it’s not free software. You can enable it as follows:

```programlisting
{ services.xserver.videoDrivers = [ "nvidia" ]; }
```

If you have an older card, you may have to use one of the legacy drivers:

```programlisting
{
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_390;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_340;
}
```

You may need to reboot after enabling this driver to prevent a clash with other kernel modules.
