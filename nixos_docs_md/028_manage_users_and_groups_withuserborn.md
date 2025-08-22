## Manage users and groups with `userborn`

### Note

This is experimental.

Like systemd-sysusers, Userborn doesn’t depend on Perl but offers some more advantages over systemd-sysusers:

1.  It can create “normal” users (with a GID \>= 1000).

2.  It can update some information about users. Most notably it can update their passwords.

3.  It will warn when users use an insecure or unsupported password hashing scheme.

Userborn is the recommended way to manage users if you don’t want to rely on the Perl script. It aims to eventually replace the Perl script by default.

You can enable Userborn via:

```programlisting
{ services.userborn.enable = true; }
```

You can configure Userborn to store the password files (`/etc/{group,passwd,shadow}`) outside of `/etc` and symlink them from this location to `/etc`:

```programlisting
{ services.userborn.passwordFilesLocation = "/persistent/etc"; }
```

This is useful when you store `/etc` on a `tmpfs` or if `/etc` is immutable (e.g. when using `system.etc.overlay.mutable = false;`). In the latter case the original files are by default stored in `/var/lib/nixos`.

Userborn implements immutable users by re-mounting the password files read-only. This means that unlike when using the Perl script, trying to add a new user (e.g. via `useradd`) will fail right away.
