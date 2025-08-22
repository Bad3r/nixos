## Building a custom kernel

Please refer to the Nixpkgs manual for the various ways of [building a custom kernel](https://nixos.org/nixpkgs/manual#sec-linux-kernel).

To use your custom kernel package in your NixOS configuration, set

```programlisting
{ boot.kernelPackages = pkgs.linuxPackagesFor yourCustomKernel; }
```
