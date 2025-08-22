## Configuring

To enable PostgreSQL, add the following to your `configuration.nix`:

```programlisting
{
  services.postgresql.enable = true;
  services.postgresql.package = pkgs.postgresql_15;
}
```

The default PostgreSQL version is approximately the latest major version available on the NixOS release matching your [`system.stateVersion`](options.html#opt-system.stateVersion). This is because PostgreSQL upgrades require a manual migration process (see below). Hence, upgrades must happen by setting [`services.postgresql.package`](options.html#opt-services.postgresql.package) explicitly.

By default, PostgreSQL stores its databases in `/var/lib/postgresql/$psqlSchema`. You can override this using [`services.postgresql.dataDir`](options.html#opt-services.postgresql.dataDir), e.g.

```programlisting
{ services.postgresql.dataDir = "/data/postgresql"; }
```
