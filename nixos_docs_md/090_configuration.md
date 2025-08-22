## Configuration

By default the module will execute Szurubooru server only, the web client only contains static files that can be reached via a reverse proxy.

Here is a basic configuration:

```programlisting
{
  services.szurubooru = {
    enable = true;

    server = {
      port = 8080;

      settings = {
        domain = "https://szurubooru.domain.tld";
        secretFile = /path/to/secret/file;
      };
    };

    database = {
      passwordFile = /path/to/secret/file;
    };
  };
}
```
