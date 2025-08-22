## `nextcloud-occ`

The management command [`occ`](https://docs.nextcloud.com/server/stable/admin_manual/occ_command.html) can be invoked by using the `nextcloud-occ` wrapper that’s globally available on a system with Nextcloud enabled.

It requires elevated permissions to become the `nextcloud` user. Given the way the privilege escalation is implemented, parameters passed via the environment to Nextcloud (e.g. `OC_PASS`) are currently ignored.

Custom service units that need to run `nextcloud-occ` either need elevated privileges or the systemd configuration from `nextcloud-setup.service` (recommended):

```programlisting
{ config, ... }:
{
  systemd.services.my-custom-service = {
    script = ''
      nextcloud-occ …
    '';
    serviceConfig = {
      inherit (config.systemd.services.nextcloud-cron.serviceConfig)
        User
        LoadCredential
        KillMode
        ;
    };
  };
}
```

Please note that the options required are subject to change. Please make sure to read the release notes when upgrading.
