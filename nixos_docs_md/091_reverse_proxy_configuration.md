## Reverse proxy configuration

The preferred method to run this service is behind a reverse proxy not to expose an open port. For example, here is a minimal Nginx configuration:

```programlisting
{
  services.szurubooru = {
    enable = true;

    server = {
      port = 8080;
      # ...

    };

    # ...

  };

  services.nginx.virtualHosts."szurubooru.domain.tld" = {
    locations = {
      "/api/".proxyPass = "http://localhost:8080/";
      "/data/".root = config.services.szurubooru.dataDir;
      "/" = {
        root = config.services.szurubooru.client.package;
        tryFiles = "$uri /index.htm";
      };
    };
  };
}
```
