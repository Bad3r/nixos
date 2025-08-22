## Using an alternative webserver as reverse-proxy (e.g. `httpd`)

By default, `nginx` is used as reverse-proxy for `nextcloud`. However, it’s possible to use e.g. `httpd` by explicitly disabling `nginx` using [`services.nginx.enable`](options.html#opt-services.nginx.enable) and fixing the settings `listen.owner` & `listen.group` in the [corresponding `phpfpm` pool](options.html#opt-services.phpfpm.pools).

An exemplary configuration may look like this:

```programlisting
{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.nginx.enable = false;
  services.nextcloud = {
    enable = true;
    hostName = "localhost";

    # further, required options

  };
  services.phpfpm.pools.nextcloud.settings = {
    "listen.owner" = config.services.httpd.user;
    "listen.group" = config.services.httpd.group;
  };
  services.httpd = {
    enable = true;
    adminAddr = "webmaster@localhost";
    extraModules = [ "proxy_fcgi" ];
    virtualHosts."localhost" = {
      documentRoot = config.services.nextcloud.package;
      extraConfig = ''
        <Directory "${config.services.nextcloud.package}">
          <FilesMatch "\.php$">
            <If "-f %{REQUEST_FILENAME}">
              SetHandler "proxy:unix:${config.services.phpfpm.pools.nextcloud.socket}|fcgi://localhost/"
            </If>
          </FilesMatch>
          <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteRule ^index\.php$ - [L]
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule . /index.php [L]
          </IfModule>
          DirectoryIndex index.php
          Require all granted
          Options +FollowSymLinks
        </Directory>
      '';
    };
  };
}
```
