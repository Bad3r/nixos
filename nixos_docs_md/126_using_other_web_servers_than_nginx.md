## Using other Web Servers than nginx

You can use other web servers by forwarding calls for `index.php` and `piwik.php` to the [`services.phpfpm.pools.<name>.socket`](options.html#opt-services.phpfpm.pools._name_.socket) fastcgi unix socket. You can use the nginx configuration in the module code as a reference to what else should be configured.
