## Basic authentication

You can configure a basic authentication to the web interface with:

```programlisting
{ ... }:

{
  services.suwayomi-server = {
    enable = true;

    openFirewall = true;

    settings = {
      server.port = 4567;
      server = {
        basicAuthEnabled = true;
        basicAuthUsername = "username";

        # NOTE: this is not a real upstream option

        basicAuthPasswordFile = ./path/to/the/password/file;
      };
    };
  };
}
```
