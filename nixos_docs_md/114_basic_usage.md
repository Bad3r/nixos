## Basic usage

Nextcloud is a PHP-based application which requires an HTTP server ([`services.nextcloud`](options.html#opt-services.nextcloud.enable) and optionally supports [`services.nginx`](options.html#opt-services.nginx.enable)).

For the database, you can set [`services.nextcloud.config.dbtype`](options.html#opt-services.nextcloud.config.dbtype) to either `sqlite` (the default), `mysql`, or `pgsql`. The simplest is `sqlite`, which will be automatically created and managed by the application. For the last two, you can easily create a local database by setting [`services.nextcloud.database.createLocally`](options.html#opt-services.nextcloud.database.createLocally) to `true`, Nextcloud will automatically be configured to connect to it through socket.

A very basic configuration may look like this:

```programlisting
{ pkgs, ... }:
{
  services.nextcloud = {
    enable = true;
    hostName = "nextcloud.tld";
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      adminpassFile = "/path/to/admin-pass-file";
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
```

The `hostName` option is used internally to configure an HTTP server using [`PHP-FPM`](https://php-fpm.org/) and `nginx`. The `config` attribute set is used by the imperative installer and all values are written to an additional file to ensure that changes can be applied by changing the module’s options.

In case the application serves multiple domains (those are checked with [`$_SERVER['HTTP_HOST']`](https://www.php.net/manual/en/reserved.variables.server.php)) it’s needed to add them to [`services.nextcloud.settings.trusted_domains`](options.html#opt-services.nextcloud.settings.trusted_domains).

Auto updates for Nextcloud apps can be enabled using [`services.nextcloud.autoUpdateApps`](options.html#opt-services.nextcloud.autoUpdateApps.enable).
