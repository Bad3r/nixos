## Profiles

**Table of Contents**

[All Hardware](#sec-profile-all-hardware)

[Base](#sec-profile-base)

[Clone Config](#sec-profile-clone-config)

[Demo](#sec-profile-demo)

[Docker Container](#sec-profile-docker-container)

[Graphical](#sec-profile-graphical)

[Hardened](#sec-profile-hardened)

[Headless](#sec-profile-headless)

[Installation Device](#sec-profile-installation-device)

[Perlless](#sec-perlless)

[Minimal](#sec-profile-minimal)

[QEMU Guest](#sec-profile-qemu-guest)

In some cases, it may be desirable to take advantage of commonly-used, predefined configurations provided by nixpkgs, but different from those that come as default. This is a role fulfilled by NixOS’s Profiles, which come as files living in `<nixpkgs/nixos/modules/profiles>`. That is to say, expected usage is to add them to the imports list of your `/etc/configuration.nix` as such:

```programlisting
{ imports = [ <nixpkgs/nixos/modules/profiles/profile-name.nix> ]; }
```

Even if some of these profiles seem only useful in the context of install media, many are actually intended to be used in real installs.

What follows is a brief explanation on the purpose and use-case for each profile. Detailing each option configured by each one is out of scope.
