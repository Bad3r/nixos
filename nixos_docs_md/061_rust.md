## Rust

The Linux kernel does not have Rust language support enabled by default. For kernel versions 6.7 or newer, experimental Rust support can be enabled. In a NixOS configuration, set:

```programlisting
{
  boot.kernelPatches = [
    {
      name = "Rust Support";
      patch = null;
      features = {
        rust = true;
      };
    }
  ];
}
```
