## Initializing the database

First, the Postgresql service must be enabled in the NixOS configuration

```programlisting
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_13;
  };
}
```

and activated with the usual

```programlisting
$ nixos-rebuild switch
```

Then you can create and seed the database, using the `setup.psql` file that you generated in the previous section, by running

```programlisting
$ sudo -u postgres psql -f setup.psql
```
