## Initializing

As of NixOS 24.05, `services.postgresql.ensureUsers.*.ensurePermissions` has been removed, after a change to default permissions in PostgreSQL 15 invalidated most of its previous use cases:

- In psql \< 15, `ALL PRIVILEGES` used to include `CREATE TABLE`, where in psql \>= 15 that would be a separate permission

- psql \>= 15 instead gives only the database owner create permissions

- Even on psql \< 15 (or databases migrated to \>= 15), it is recommended to manually assign permissions along these lines
  - https://www.postgresql.org/docs/release/15.0/

  - https://www.postgresql.org/docs/15/ddl-schemas.html#DDL-SCHEMAS-PRIV

### Assigning ownership

Usually, the database owner should be a database user of the same name. This can be done with `services.postgresql.ensureUsers.*.ensureDBOwnership = true;`.

If the database user name equals the connecting system user name, postgres by default will accept a passwordless connection via unix domain socket. This makes it possible to run many postgres-backed services without creating any database secrets at all.

### Assigning extra permissions

For many cases, it will be enough to have the database user be the owner. Until `services.postgresql.ensureUsers.*.ensurePermissions` has been re-thought, if more users need access to the database, please use one of the following approaches:

**WARNING:** `services.postgresql.initialScript` is not recommended for `ensurePermissions` replacement, as that is _only run on first start of PostgreSQL_.

**NOTE:** all of these methods may be obsoleted, when `ensure*` is reworked, but it is expected that they will stay viable for running database migrations.

**NOTE:** please make sure that any added migrations are idempotent (re-runnable).

#### in database’s setup `postStart`

`ensureUsers` is run in `postgresql-setup`, so this is where `postStart` must be added to:

```programlisting
{
  systemd.services.postgresql-setup.postStart = ''
    psql service1 -c 'GRANT SELECT ON ALL TABLES IN SCHEMA public TO "extraUser1"'
    psql service1 -c 'GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO "extraUser1"'
    # ....

  '';
}
```

#### in intermediate oneshot service

Make sure to run this service after `postgresql.target`, not `postgresql.service`.

They differ in two aspects:

- `postgresql.target` includes `postgresql-setup`, so users managed via `ensureUsers` are already created.

- `postgresql.target` will wait until PostgreSQL is in read-write mode after restoring from backup, while `postgresql.service` will already be ready when PostgreSQL is still recovering in read-only mode.

Both can lead to unexpected errors either during initial database creation or restore, when using `postgresql.service`.

```programlisting
{
  systemd.services."migrate-service1-db1" = {
    serviceConfig.Type = "oneshot";
    requiredBy = "service1.service";
    before = "service1.service";
    after = "postgresql.target";
    serviceConfig.User = "postgres";
    environment.PGPORT = toString services.postgresql.settings.port;
    path = [ postgresql ];
    script = ''
      psql service1 -c 'GRANT SELECT ON ALL TABLES IN SCHEMA public TO "extraUser1"'
      psql service1 -c 'GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO "extraUser1"'
      # ....

    '';
  };
}
```
