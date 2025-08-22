## Basic usage

By default, the module will execute Suwayomi-Server backend and web UI:

```programlisting
{ ... }:

{
  services.suwayomi-server = {
    enable = true;
  };
}
```

It runs in the systemd service named `suwayomi-server` in the data directory `/var/lib/suwayomi-server`.

You can change the default parameters with some other parameters:

```programlisting
{ ... }:

{
  services.suwayomi-server = {
    enable = true;

    dataDir = "/var/lib/suwayomi"; # Default is "/var/lib/suwayomi-server"

    openFirewall = true;

    settings = {
      server.port = 4567;
    };
  };
}
```

If you want to create a desktop icon, you can activate the system tray option:

```programlisting
{ ... }:

{
  services.suwayomi-server = {
    enable = true;

    dataDir = "/var/lib/suwayomi"; # Default is "/var/lib/suwayomi-server"

    openFirewall = true;

    settings = {
      server.port = 4567;
      server.enableSystemTray = true;
    };
  };
}
```
