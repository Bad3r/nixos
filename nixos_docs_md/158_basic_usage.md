## Basic usage

A minimal configuration using Let’s Encrypt for TLS certificates looks like this:

```programlisting
{
  services.discourse = {
    enable = true;
    hostname = "discourse.example.com";
    admin = {
      email = "admin@example.com";
      username = "admin";
      fullName = "Administrator";
      passwordFile = "/path/to/password_file";
    };
    secretKeyBaseFile = "/path/to/secret_key_base_file";
  };
  security.acme.email = "me@example.com";
  security.acme.acceptTerms = true;
}
```

Provided a proper DNS setup, you’ll be able to connect to the instance at `discourse.example.com` and log in using the credentials provided in `services.discourse.admin`.
