## Prerequisites

The `gitlab` service exposes only an Unix socket at `/run/gitlab/gitlab-workhorse.socket`. You need to configure a webserver to proxy HTTP requests to the socket.

For instance, the following configuration could be used to use nginx as frontend proxy:

```programlisting
{
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."git.example.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
    };
  };
}
```
