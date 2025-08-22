## Service configuration

The following configuration sets up the PostgreSQL as database backend and binds GoToSocial to `127.0.0.1:8080`, expecting to be run behind a HTTP proxy on `gotosocial.example.com`.

```programlisting
{
  services.gotosocial = {
    enable = true;
    setupPostgresqlDB = true;
    settings = {
      application-name = "My GoToSocial";
      host = "gotosocial.example.com";
      protocol = "https";
      bind-address = "127.0.0.1";
      port = 8080;
    };
  };
}
```

Please refer to the [GoToSocial Documentation](https://docs.gotosocial.org/en/latest/configuration/general/) for additional configuration options.
