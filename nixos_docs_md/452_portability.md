## Portability

It is possible to write service modules that are portable. This is done by either avoiding the `systemd` option tree, or by defining process-manager-specific definitions in an optional way:

```programlisting
{
  config,
  options,
  lib,
  ...
}:
{
  _class = "service";
  config = {
    process.argv = [ (lib.getExe config.foo.program) ];
  }
  // lib.optionalAttrs (options ? systemd) {
    # ... systemd-specific definitions ...

  };
}
```

This way, the module can be loaded into a configuration manager that does not use systemd, and the `systemd` definitions will be ignored. Similarly, other configuration managers can declare their own options for services to customize.
