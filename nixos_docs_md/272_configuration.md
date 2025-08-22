## Configuration

When enabled, this module automatically creates a systemd service to start the `dump1090-fa` application. The application will then write its JSON output files to `/run/dump1090-fa`.

Exposing the integrated web interface is left to the user’s configuration. Below is a minimal example demonstrating how to serve it using Nginx:

```programlisting
{ pkgs, ... }:
{
  services.dump1090-fa.enable = true;

  services.nginx = {
    enable = true;
    virtualHosts."dump1090-fa" = {
      locations = {
        "/".alias = "${pkgs.dump1090-fa}/share/dump1090/";
        "/data/".alias = "/run/dump1090-fa/";
      };
    };
  };
}
```
