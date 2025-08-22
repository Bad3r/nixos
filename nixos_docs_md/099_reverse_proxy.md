## Reverse Proxy

You can configure nginx as a reverse proxy with:

```programlisting
{ ... }:

{
  security.acme = {
    acceptTerms = true;
    defaults.email = "foo@bar.com";
  };

  services.nginx.enable = true;
  services.nginx.virtualHosts."strfry.example.com" = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.strfry.settings.relay.port}";
      proxyWebsockets = true; # nostr uses websockets

    };
  };

  services.strfry.enable = true;
}
```
