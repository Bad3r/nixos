## Procedural Languages

PostgreSQL ships the additional procedural languages PL/Perl, PL/Python and PL/Tcl as extensions. They are packaged as plugins and can be made available in the same way as external extensions:

```programlisting
{
  services.postgresql.extensions =
    ps: with ps; [
      plperl
      plpython3
      pltcl
    ];
}
```

Each procedural language plugin provides a `.withPackages` helper to make language specific packages available at run-time.

For example, to make `python3Packages.base58` available:

```programlisting
{
  services.postgresql.extensions =
    pgps: with pgps; [ (plpython3.withPackages (pyps: with pyps; [ base58 ])) ];
}
```

This currently works for:

- `plperl` by re-using `perl.withPackages`

- `plpython3` by re-using `python3.withPackages`

- `plr` by exposing `rPackages`

- `pltcl` by exposing `tclPackages`
