## Proxy configuration

Although it is possible to expose GoToSocial directly, it is common practice to operate it behind an HTTP reverse proxy such as nginx.

```programlisting
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  services.nginx = {
    enable = true;
    clientMaxBodySize = "40M";
    virtualHosts = with config.services.gotosocial.settings; {
      "${host}" = {
        enableACME = true;
        forceSSL = true;
        locations = {
          "/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://${bind-address}:${toString port}";
          };
        };
      };
    };
  };
}
```

Please refer to [_SSL/TLS Certificates with ACME_](#module-security-acme "SSL/TLS Certificates with ACME") for details on how to provision an SSL/TLS certificate.
