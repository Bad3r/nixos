## Practical Instructions

To build an ISO image for the channel `nixos-unstable`:

```programlisting
$ git clone https://github.com/NixOS/nixpkgs.git
$ cd nixpkgs/nixos
$ git switch nixos-unstable
$ nix-build -A config.system.build.isoImage -I nixos-config=modules/installer/cd-dvd/installation-cd-minimal.nix default.nix
```

To check the content of an ISO image, mount it like so:

```programlisting

# mount -o loop -t iso9660 ./result/iso/nixos-image-25.05pre-git-x86_64-linux.iso /mnt/iso

```
