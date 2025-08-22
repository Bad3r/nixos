## Quickstart

A minimal configuration for Mosquitto is

```programlisting
{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
    ];
  };
}
```

This will start a broker on port 1883, listening on all interfaces of the machine, allowing read/write access to all topics to any user without password requirements.

User authentication can be configured with the `users` key of listeners. A config that gives full read access to a user `monitor` and restricted write access to a user `service` could look like

```programlisting
{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        users = {
          monitor = {
            acl = [ "read #" ];
            password = "monitor";
          };
          service = {
            acl = [ "write service/#" ];
            password = "service";
          };
        };
      }
    ];
  };
}
```

TLS authentication is configured by setting TLS-related options of the listener:

```programlisting
{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 8883; # port change is not required, but helpful to avoid mistakes

        # ...

        settings = {
          cafile = "/path/to/mqtt.ca.pem";
          certfile = "/path/to/mqtt.pem";
          keyfile = "/path/to/mqtt.key";
        };
      }
    ];
  };
}
```
