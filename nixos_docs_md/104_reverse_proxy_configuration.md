## Reverse proxy configuration

The preferred method to run this service is behind a reverse proxy not to expose an open port. This, you can configure Nginx such like this:

```programlisting
{
  services-pingvin-share = {
    enable = true;

    hostname = "pingvin-share.domain.tld";
    https = true;

    nginx.enable = true;
  };
}
```

Furthermore, you can increase the maximal size of an uploaded file with the option [services.nginx.clientMaxBodySize](options.html#opt-services.nginx.clientMaxBodySize).
