## Additional drivers or firmware

If you need additional (non-distributable) drivers or firmware in the installer, you might want to extend these configurations.

For example, to build the GNOME graphical installer ISO, but with support for certain WiFi adapters present in some MacBooks, you can create the following file at `modules/installer/cd-dvd/installation-cd-graphical-gnome-macbook.nix`:

```programlisting
{ config, ... }:

{
  imports = [ ./installation-cd-graphical-gnome.nix ];

  boot.initrd.kernelModules = [ "wl" ];

  boot.kernelModules = [
    "kvm-intel"
    "wl"
  ];
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
}
```

Then build it like in the example above:

```programlisting
$ git clone https://github.com/NixOS/nixpkgs.git
$ cd nixpkgs/nixos
$ export NIXPKGS_ALLOW_UNFREE=1
$ nix-build -A config.system.build.isoImage -I nixos-config=modules/installer/cd-dvd/installation-cd-graphical-gnome-macbook.nix default.nix
```
