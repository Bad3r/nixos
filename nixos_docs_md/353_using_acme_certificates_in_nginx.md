## Using ACME certificates in Nginx

NixOS supports fetching ACME certificates for you by setting `enableACME = true;` in a virtualHost config. We first create self-signed placeholder certificates in place of the real ACME certs. The placeholder certs are overwritten when the ACME certs arrive. For `foo.example.com` the config would look like this:

```programlisting
{
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "admin+acme@example.com";
  services.nginx = {
    enable = true;
    virtualHosts = {
      "foo.example.com" = {
        forceSSL = true;
        enableACME = true;
        # All serverAliases will be added as extra domain names on the certificate.

        serverAliases = [ "bar.example.com" ];
        locations."/" = {
          root = "/var/www";
        };
      };

      # We can also add a different vhost and reuse the same certificate

      # but we have to append extraDomainNames manually beforehand:

      # security.acme.certs."foo.example.com".extraDomainNames = [ "baz.example.com" ];

      "baz.example.com" = {
        forceSSL = true;
        useACMEHost = "foo.example.com";
        locations."/" = {
          root = "/var/www";
        };
      };
    };
  };
}
```
