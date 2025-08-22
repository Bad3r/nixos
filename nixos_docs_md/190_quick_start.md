## Quick Start

```programlisting
{
  services.umurmur = {
    enable = true;
    openFirewall = true;
    settings = {
      port = 7365;
      channels = [
        {
          name = "root";
          parent = "";
          description = "Root channel. No entry.";
          noenter = true;
        }
        {
          name = "lobby";
          parent = "root";
          description = "Lobby channel";
        }
      ];
      default_channel = "lobby";
    };
  };
}
```

See a full configuration in [umurmur.conf.example](https://github.com/umurmur/umurmur/blob/master/umurmur.conf.example)
