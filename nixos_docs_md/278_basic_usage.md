## Basic Usage

By default, the module creates a [`systemd`](https://www.freedesktop.org/wiki/Software/systemd/) unit which runs the sync server with an isolated user using the systemd `DynamicUser` option.

This can be done by enabling the `anki-sync-server` service:

```programlisting
{ ... }:

{
  services.anki-sync-server.enable = true;
}
```

It is necessary to set at least one username-password pair under `services.anki-sync-server.users`. For example

```programlisting
{
  services.anki-sync-server.users = [
    {
      username = "user";
      passwordFile = /etc/anki-sync-server/user;
    }
  ];
}
```

Here, `passwordFile` is the path to a file containing just the password in plaintext. Make sure to set permissions to make this file unreadable to any user besides root.

By default, synced data are stored in */var/lib/anki-sync-server/*ankiuser\*\*. You can change the directory by using `services.anki-sync-server.baseDirectory`

```programlisting
{ services.anki-sync-server.baseDirectory = "/home/anki/data"; }
```

By default, the server listen address `services.anki-sync-server.host` is set to localhost, listening on port `services.anki-sync-server.port`, and does not open the firewall. This is suitable for purely local testing, or to be used behind a reverse proxy. If you want to expose the sync server directly to other computers (not recommended in most circumstances, because the sync server doesn’t use HTTPS), then set the following options:

```programlisting
{
  services.anki-sync-server.address = "0.0.0.0";
  services.anki-sync-server.openFirewall = true;
}
```
