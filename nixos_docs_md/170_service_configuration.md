## Service configuration

The Elixir configuration file required by Akkoma is generated automatically from [`services.akkoma.config`](options.html#opt-services.akkoma.config). Secrets must be included from external files outside of the Nix store by setting the configuration option to an attribute set containing the attribute `_secret` – a string pointing to the file containing the actual value of the option.

For the mandatory configuration settings these secrets will be generated automatically if the referenced file does not exist during startup, unless disabled through [`services.akkoma.initSecrets`](options.html#opt-services.akkoma.initSecrets).

The following configuration binds Akkoma to the Unix socket `/run/akkoma/socket`, expecting to be run behind a HTTP proxy on `fediverse.example.com`.

```programlisting
{
  services.akkoma.enable = true;
  services.akkoma.config = {
    ":pleroma" = {
      ":instance" = {
        name = "My Akkoma instance";
        description = "More detailed description";
        email = "admin@example.com";
        registration_open = false;
      };

      "Pleroma.Web.Endpoint" = {
        url.host = "fediverse.example.com";
      };
    };
  };
}
```

Please refer to the [configuration cheat sheet](https://docs.akkoma.dev/stable/configuration/cheatsheet/) for additional configuration options.
