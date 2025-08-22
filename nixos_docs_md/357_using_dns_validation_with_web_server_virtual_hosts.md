## Using DNS validation with web server virtual hosts

It is possible to use DNS-01 validation with all certificates, including those automatically configured via the Nginx/Apache [`enableACME`](options.html#opt-services.nginx.virtualHosts._name_.enableACME) option. This configuration pattern is fully supported and part of the module’s test suite for Nginx + Apache.

You must follow the guide above on configuring DNS-01 validation first, however instead of setting the options for one certificate (e.g. [`security.acme.certs.<name>.dnsProvider`](options.html#opt-security.acme.certs._name_.dnsProvider)) you will set them as defaults (e.g. [`security.acme.defaults.dnsProvider`](options.html#opt-security.acme.defaults.dnsProvider)).

```programlisting
{
  # Configure ACME appropriately

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "admin+acme@example.com";
  security.acme.defaults = {
    dnsProvider = "rfc2136";
    environmentFile = "/var/lib/secrets/certs.secret";
    # We don't need to wait for propagation since this is a local DNS server

    dnsPropagationCheck = false;
  };

  # For each virtual host you would like to use DNS-01 validation with,

  # set acmeRoot = null

  services.nginx = {
    enable = true;
    virtualHosts = {
      "foo.example.com" = {
        enableACME = true;
        acmeRoot = null;
      };
    };
  };
}
```

And that’s it! Next time your configuration is rebuilt, or when you add a new virtualHost, it will be DNS-01 validated.
