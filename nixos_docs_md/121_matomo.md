## Matomo

**Table of Contents**

[Database Setup](#module-services-matomo-database-setup)

[Archive Processing](#module-services-matomo-archive-processing)

[Backup](#module-services-matomo-backups)

[Issues](#module-services-matomo-issues)

[Using other Web Servers than nginx](#module-services-matomo-other-web-servers)

Matomo is a real-time web analytics application. This module configures php-fpm as backend for Matomo, optionally configuring an nginx vhost as well.

An automatic setup is not supported by Matomo, so you need to configure Matomo itself in the browser-based Matomo setup.
