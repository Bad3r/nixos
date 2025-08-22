## Create users and groups with `systemd-sysusers`

### Note

This is experimental.

Please consider using [Userborn](#sec-userborn "Manage users and groups with userborn") over systemd-sysusers as it’s more feature complete.

Instead of using a custom perl script to create users and groups, you can use systemd-sysusers:

```programlisting
{ systemd.sysusers.enable = true; }
```

The primary benefit of this is to remove a dependency on perl.
