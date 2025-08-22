## Example configuration

A basic configuration with some custom settings could look like this:

```programlisting
{
  services.keycloak = {
    enable = true;
    settings = {
      hostname = "keycloak.example.com";
      hostname-strict-backchannel = true;
    };
    initialAdminPassword = "e6Wcm0RrtegMEHl"; # change on first login

    sslCertificate = "/run/keys/ssl_cert";
    sslCertificateKey = "/run/keys/ssl_key";
    database.passwordFile = "/run/keys/db_password";
  };
}
```
