## Necessary system state

**Table of Contents**

[NixOS](#sec-nixos-state)

[systemd](#sec-systemd-state)

[ZFS](#sec-zfs-state)

Normally — on systems with a persistent `rootfs` — system services can persist state to the filesystem without administrator intervention.

However, it is possible and not-uncommon to create [impermanent systems](https://wiki.nixos.org/wiki/Impermanence), whose `rootfs` is either a `tmpfs` or reset during boot. While NixOS itself supports this kind of configuration, special care needs to be taken.
