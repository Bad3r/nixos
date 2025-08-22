## Plugins

The collection of plugins for each PostgreSQL version can be accessed with `.pkgs`. For example, for the `pkgs.postgresql_15` package, its plugin collection is accessed by `pkgs.postgresql_15.pkgs`:

```programlisting
$ nix repl '<nixpkgs>'

Loading '<nixpkgs>'...
Added 10574 variables.

nix-repl> postgresql_15.pkgs.<TAB><TAB>
postgresql_15.pkgs.cstore_fdw        postgresql_15.pkgs.pg_repack
postgresql_15.pkgs.pg_auto_failover  postgresql_15.pkgs.pg_safeupdate
postgresql_15.pkgs.pg_bigm           postgresql_15.pkgs.pg_similarity
postgresql_15.pkgs.pg_cron           postgresql_15.pkgs.pg_topn
postgresql_15.pkgs.pg_hll            postgresql_15.pkgs.pgjwt
postgresql_15.pkgs.pg_partman        postgresql_15.pkgs.pgroonga
...
```

To add plugins via NixOS configuration, set `services.postgresql.extensions`:

```programlisting
{
  services.postgresql.package = pkgs.postgresql_17;
  services.postgresql.extensions =
    ps: with ps; [
      pg_repack
      postgis
    ];
}
```

You can build a custom `postgresql-with-plugins` (to be used outside of NixOS) using the function `.withPackages`. For example, creating a custom PostgreSQL package in an overlay can look like this:

```programlisting
self: super: {
  postgresql_custom = self.postgresql_17.withPackages (ps: [
    ps.pg_repack
    ps.postgis
  ]);
}
```

Here’s a recipe on how to override a particular plugin through an overlay:

```programlisting
self: super: {
  postgresql_15 = super.postgresql_15 // {
    pkgs = super.postgresql_15.pkgs // {
      pg_repack = super.postgresql_15.pkgs.pg_repack.overrideAttrs (_: {
        name = "pg_repack-v20181024";
        src = self.fetchzip {
          url = "https://github.com/reorg/pg_repack/archive/923fa2f3c709a506e111cc963034bf2fd127aa00.tar.gz";
          sha256 = "17k6hq9xaax87yz79j773qyigm4fwk8z4zh5cyp6z0sxnwfqxxw5";
        };
      });
    };
  };
}
```
