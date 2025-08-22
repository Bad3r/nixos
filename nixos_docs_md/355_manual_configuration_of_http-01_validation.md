## Manual configuration of HTTP-01 validation

First off you will need to set up a virtual host to serve the challenges. This example uses a vhost called `certs.example.com`, with the intent that you will generate certs for all your vhosts and redirect everyone to HTTPS.

```programlisting
{
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "admin+acme@example.com";

  # /var/lib/acme/.challenges must be writable by the ACME user

  # and readable by the Nginx user. The easiest way to achieve

  # this is to add the Nginx user to the ACME group.

  users.users.nginx.extraGroups = [ "acme" ];

  services.nginx = {
    enable = true;
    virtualHosts = {
      "acmechallenge.example.com" = {
        # Catchall vhost, will redirect users to HTTPS for all vhosts

        serverAliases = [ "*.example.com" ];
        locations."/.well-known/acme-challenge" = {
          root = "/var/lib/acme/.challenges";
        };
        locations."/" = {
          return = "301 https://$host$request_uri";
        };
      };
    };
  };
  # Alternative config for Apache

  users.users.wwwrun.extraGroups = [ "acme" ];
  services.httpd = {
    enable = true;
    virtualHosts = {
      "acmechallenge.example.com" = {
        # Catchall vhost, will redirect users to HTTPS for all vhosts

        serverAliases = [ "*.example.com" ];
        # /var/lib/acme/.challenges must be writable by the ACME user and readable by the Apache user.

        # By default, this is the case.

        documentRoot = "/var/lib/acme/.challenges";
        extraConfig = ''
          RewriteEngine On
          RewriteCond %{HTTPS} off
          RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge [NC]
          RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301]
        '';
      };
    };
  };
}
```

Now you need to configure ACME to generate a certificate.

```programlisting
{
  security.acme.certs."foo.example.com" = {
    webroot = "/var/lib/acme/.challenges";
    email = "foo@example.com";
    # Ensure that the web server you use can read the generated certs

    # Take a look at the group option for the web server you choose.

    group = "nginx";
    # Since we have a wildcard vhost to handle port 80,

    # we can generate certs for anything!

    # Just make sure your DNS resolves them.

    extraDomainNames = [ "mail.example.com" ];
  };
}
```

The private key `key.pem` and certificate `fullchain.pem` will be put into `/var/lib/acme/foo.example.com`.

Refer to [Appendix A](options.html "Appendix A. Configuration Options") for all available configuration options for the [security.acme](options.html#opt-security.acme.certs) module.
