## Let’s Encrypt Configuration

As you can see in the code snippet from the [previous section](#module-services-prosody-basic-usage "Basic usage"), you’ll need a single TLS certificate covering your main endpoint, the MUC one as well as the HTTP Upload one. We can generate such a certificate by leveraging the ACME [extraDomainNames](options.html#opt-security.acme.certs._name_.extraDomainNames) module option.

Provided the setup detailed in the previous section, you’ll need the following acme configuration to generate a TLS certificate for the three endponits:

```programlisting
{
  security.acme = {
    email = "root@example.org";
    acceptTerms = true;
    certs = {
      "example.org" = {
        webroot = "/var/www/example.org";
        email = "root@example.org";
        extraDomainNames = [
          "conference.example.org"
          "upload.example.org"
        ];
      };
    };
  };
}
```
