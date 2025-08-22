## Authentication

Local connections are made through unix sockets by default and support [peer authentication](https://www.postgresql.org/docs/current/auth-peer.html). This allows system users to login with database roles of the same name. For example, the `postgres` system user is allowed to login with the database role `postgres`.

System users and database roles might not always match. In this case, to allow access for a service, you can create a [user name map](https://www.postgresql.org/docs/current/auth-username-maps.html) between system roles and an existing database role.

### User Mapping

Assume that your app creates a role `admin` and you want the `root` user to be able to login with it. You can then use [`services.postgresql.identMap`](options.html#opt-services.postgresql.identMap) to define the map and [`services.postgresql.authentication`](options.html#opt-services.postgresql.authentication) to enable it:

```programlisting
{
  services.postgresql = {
    identMap = ''
      admin root admin
    '';
    authentication = ''
      local all admin peer map=admin
    '';
  };
}
```

### Warning

To avoid conflicts with other modules, you should never apply a map to `all` roles. Because PostgreSQL will stop on the first matching line in `pg_hba.conf`, a line matching all roles would lock out other services. Each module should only manage user maps for the database roles that belong to this module. Best practice is to name the map after the database role it manages to avoid name conflicts.
