## Using a regular TLS certificate

To set up TLS using a regular certificate and key on file, use the [`services.discourse.sslCertificate`](options.html#opt-services.discourse.sslCertificate) and [`services.discourse.sslCertificateKey`](options.html#opt-services.discourse.sslCertificateKey) options:

```programlisting
{
  services.discourse = {
    enable = true;
    hostname = "discourse.example.com";
    sslCertificate = "/path/to/ssl_certificate";
    sslCertificateKey = "/path/to/ssl_certificate_key";
    admin = {
      email = "admin@example.com";
      username = "admin";
      fullName = "Administrator";
      passwordFile = "/path/to/password_file";
    };
    secretKeyBaseFile = "/path/to/secret_key_base_file";
  };
}
```
