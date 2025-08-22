## Nix Store Partition

You can define a partition that only contains the Nix store and then mount it under `/nix/store`. Because the `/nix/store` part of the paths is already determined by the mount point, you have to set `stripNixStorePrefix = true;` so that the prefix is stripped from the paths before copying them into the image.

```programlisting
{
  fileSystems."/nix/store".device = "/dev/disk/by-partlabel/nix-store";

  image.repart.partitions = {
    "store" = {
      storePaths = [ config.system.build.toplevel ];
      stripNixStorePrefix = true;
      repartConfig = {
        Type = "linux-generic";
        Label = "nix-store";
        # ...

      };
    };
  };
}
```
