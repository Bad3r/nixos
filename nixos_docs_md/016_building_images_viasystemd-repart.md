## Building Images via `systemd-repart`

**Table of Contents**

[Nix Store Partition](#sec-image-repart-store-partition)

[Appliance Image](#sec-image-repart-appliance)

You can build disk images in NixOS with the `image.repart` option provided by the module [image/repart.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/image/repart.nix). This module uses `systemd-repart` to build the images and exposes it’s entire interface via the `repartConfig` option.

An example of how to build an image:

```programlisting
{ config, modulesPath, ... }:
{

  imports = [ "${modulesPath}/image/repart.nix" ];

  image.repart = {
    name = "image";
    partitions = {
      "esp" = {
        contents = {
          # ...

        };
        repartConfig = {
          Type = "esp";
          # ...

        };
      };
      "root" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "root";
          Label = "nixos";
          # ...

        };
      };
    };
  };

}
```
