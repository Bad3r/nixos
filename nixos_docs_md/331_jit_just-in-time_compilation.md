## JIT (Just-In-Time compilation)

[JIT](https://www.postgresql.org/docs/current/jit-reason.html)-support in the PostgreSQL package is disabled by default because of the ~600MiB closure-size increase from the LLVM dependency. It can be optionally enabled in PostgreSQL with the following config option:

```programlisting
{ services.postgresql.enableJIT = true; }
```

This makes sure that the [`jit`](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-JIT)-setting is set to `on` and a PostgreSQL package with JIT enabled is used. Further tweaking of the JIT compiler, e.g. setting a different query cost threshold via [`jit_above_cost`](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-JIT-ABOVE-COST) can be done manually via [`services.postgresql.settings`](options.html#opt-services.postgresql.settings).

The attribute-names of JIT-enabled PostgreSQL packages are suffixed with `_jit`, i.e. for each `pkgs.postgresql` (and `pkgs.postgresql_<major>`) in `nixpkgs` there’s also a `pkgs.postgresql_jit` (and `pkgs.postgresql_<major>_jit`). Alternatively, a JIT-enabled variant can be derived from a given `postgresql` package via `postgresql.withJIT`. This is also useful if it’s not clear which attribute from `nixpkgs` was originally used (e.g. when working with [`config.services.postgresql.package`](options.html#opt-services.postgresql.package) or if the package was modified via an overlay) since all modifications are propagated to `withJIT`. I.e.

```programlisting
with import <nixpkgs> {
  overlays = [
    (self: super: {
      postgresql = super.postgresql.overrideAttrs (_: {
        pname = "foobar";
      });
    })
  ];
};
postgresql.withJIT.pname
```

evaluates to `"foobar"`.
