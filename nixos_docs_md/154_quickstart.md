## Quickstart

Checkout the [configuration docs](https://github.com/glanceapp/glance/blob/main/docs/configuration.md) to learn more. Use the following configuration to start a public instance of Glance locally:

```programlisting
{
  services.glance = {
    enable = true;
    settings = {
      pages = [
        {
          name = "Home";
          columns = [
            {
              size = "full";
              widgets = [
                { type = "calendar"; }
                {
                  type = "weather";
                  location = "Nivelles, Belgium";
                }
              ];
            }
          ];
        }
      ];
    };
    openFirewall = true;
  };
}
```
