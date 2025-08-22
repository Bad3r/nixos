## Building a NixOS (Live) ISO

**Table of Contents**

[Practical Instructions](#sec-building-image-instructions)

[Additional drivers or firmware](#sec-building-image-drivers)

[Technical Notes](#sec-building-image-tech-notes)

Default live installer configurations are available inside `nixos/modules/installer/cd-dvd`. For building other system images, see [Building Images with `nixos-rebuild build-image`](#sec-image-nixos-rebuild-build-image "Building Images with nixos-rebuild build-image").

You have two options:

- Use any of those default configurations as is

- Combine them with (any of) your host config(s)

System images, such as the live installer ones, know how to enforce configuration settings on which they immediately depend in order to work correctly.

However, if you are confident, you can opt to override those enforced values with `mkForce`.
