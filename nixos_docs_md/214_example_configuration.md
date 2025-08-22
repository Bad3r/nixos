## Example Configuration

```programlisting
{
  services.jotta-cli = {
    enable = true;
    options = [ "slow" ];
    package = pkgs.jotta-cli;
  };
}
```

This uses `jotta-cli` and `jottad` from the `pkgs.jotta-cli` package and starts `jottad` in low memory mode.

`jottad` is also added to `environment.systemPackages`, so `jottad --help` can be used to explore options.
