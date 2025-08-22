## Basic usage

A very basic configuration may look like this:

```programlisting
{ pkgs, ... }:
{
  services.grocy = {
    enable = true;
    hostName = "grocy.tld";
  };
}
```

This configures a simple vhost using [nginx](options.html#opt-services.nginx.enable) which listens to `grocy.tld` with fully configured ACME/LE (this can be disabled by setting [services.grocy.nginx.enableSSL](options.html#opt-services.grocy.nginx.enableSSL) to `false`). After the initial setup the credentials `admin:admin` can be used to login.

The application’s state is persisted at `/var/lib/grocy/grocy.db` in a `sqlite3` database. The migration is applied when requesting the `/`-route of the application.
