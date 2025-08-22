## Basic usage for a caching proxy configuration

A very basic configuration for Athens that acts as a caching and forwarding HTTP proxy is:

```programlisting
{
  services.athens = {
    enable = true;
  };
}
```

If you want to prevent Athens from writing to disk, you can instead configure it to cache modules only in memory:

```programlisting
{
  services.athens = {
    enable = true;
    storageType = "memory";
  };
}
```

To use the local proxy in Go builds (outside of `nix`), you can set the proxy as environment variable:

```programlisting
{
  environment.variables = {
    GOPROXY = "http://localhost:3000";
  };
}
```

To also use the local proxy for Go builds happening in `nix` (with `buildGoModule`), the nix daemon can be configured to pass the GOPROXY environment variable to the `goModules` fixed-output derivation.

This can either be done via the nix-daemon systemd unit:

```programlisting
{ systemd.services.nix-daemon.environment.GOPROXY = "http://localhost:3000"; }
```

or via the [impure-env experimental feature](https://nix.dev/manual/nix/2.24/command-ref/conf-file#conf-impure-env):

```programlisting
{
  nix.settings.experimental-features = [ "configurable-impure-env" ];
  nix.settings.impure-env = "GOPROXY=http://localhost:3000";
}
```
