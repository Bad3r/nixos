## Extra configuration

Not all configuration options of the server are available directly in this module, but you can add them in `services.szurubooru.server.settings`:

```programlisting
{
  services.szurubooru = {
    enable = true;

    server.settings = {
      domain = "https://szurubooru.domain.tld";
      delete_source_files = "yes";
      contact_email = "example@domain.tld";
    };
  };
}
```

You can find all of the options in the default config file available [here](https://github.com/rr-/szurubooru/blob/master/server/config.yaml.dist).
