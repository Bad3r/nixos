## Extensions mechanism

Bootspec cannot account for all usecases.

For this purpose, Bootspec offers a generic extension facility [`boot.bootspec.extensions`](options.html#opt-boot.bootspec.extensions) which can be used to inject any data needed for your usecases.

An example for SecureBoot is to get the Nix store path to `/etc/os-release` in order to bake it into a unified kernel image:

```programlisting
{ config, lib, ... }:
{
  boot.bootspec.extensions = {
    "org.secureboot.osRelease" = config.environment.etc."os-release".source;
  };
}
```

To reduce incompatibility and prevent names from clashing between applications, it is **highly recommended** to use a unique namespace for your extensions.
