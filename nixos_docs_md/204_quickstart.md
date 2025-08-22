## Quickstart

To fully setup Netbird as a self-hosted server, we need both a Coturn server and an identity provider, the list of supported SSOs and their setup are available [on Netbird’s documentation](https://docs.netbird.io/selfhosted/selfhosted-guide#step-3-configure-identity-provider-idp).

There are quite a few settings that need to be passed to Netbird for it to function, and a minimal config looks like :

```programlisting
{
  services.netbird.server = {
    enable = true;

    domain = "netbird.example.selfhosted";

    enableNginx = true;

    coturn = {
      enable = true;

      passwordFile = "/path/to/a/secret/password";
    };

    management = {
      oidcConfigEndpoint = "https://sso.example.selfhosted/oauth2/openid/netbird/.well-known/openid-configuration";

      settings = {
        TURNConfig = {
          Turns = [
            {
              Proto = "udp";
              URI = "turn:netbird.example.selfhosted:3478";
              Username = "netbird";
              Password._secret = "/path/to/a/secret/password";
            }
          ];
        };
      };
    };
  };
}
```
