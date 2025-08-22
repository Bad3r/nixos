## Nextcloud

**Table of Contents**

[Basic usage](#module-services-nextcloud-basic-usage)

[`nextcloud-occ`](#module-services-nextcloud-occ)

[Common problems](#module-services-nextcloud-pitfalls-during-upgrade)

[Using an alternative webserver as reverse-proxy (e.g. `httpd`)](#module-services-nextcloud-httpd)

[Installing Apps and PHP extensions](#installing-apps-php-extensions-nextcloud)

[Known warnings](#module-services-nextcloud-known-warnings)

[Maintainer information](#module-services-nextcloud-maintainer-info)

[Nextcloud](https://nextcloud.com/) is an open-source, self-hostable cloud platform. The server setup can be automated using [services.nextcloud](options.html#opt-services.nextcloud.enable). A desktop client is packaged at `pkgs.nextcloud-client`.

The current default by NixOS is `nextcloud31` which is also the latest major version available.
