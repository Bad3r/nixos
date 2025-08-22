## Using ACME with services demanding root owned certificates

Some services refuse to start if the configured certificate files are not owned by root. PostgreSQL and OpenSMTPD are examples of these. There is no way to change the user the ACME module uses (it will always be `acme`), however you can use systemd’s `LoadCredential` feature to resolve this elegantly. Below is an example configuration for OpenSMTPD, but this pattern can be applied to any service.

```programlisting
{
  # Configure ACME however you like (DNS or HTTP validation), adding

  # the following configuration for the relevant certificate.

  # Note: You cannot use `systemctl reload` here as that would mean

  # the LoadCredential configuration below would be skipped and

  # the service would continue to use old certificates.

  security.acme.certs."mail.example.com".postRun = ''
    systemctl restart opensmtpd
  '';

  # Now you must augment OpenSMTPD's systemd service to load

  # the certificate files.

  systemd.services.opensmtpd.requires = [ "acme-mail.example.com.service" ];
  systemd.services.opensmtpd.serviceConfig.LoadCredential =
    let
      certDir = config.security.acme.certs."mail.example.com".directory;
    in
    [
      "cert.pem:${certDir}/cert.pem"
      "key.pem:${certDir}/key.pem"
    ];

  # Finally, configure OpenSMTPD to use these certs.

  services.opensmtpd =
    let
      credsDir = "/run/credentials/opensmtpd.service";
    in
    {
      enable = true;
      setSendmail = false;
      serverConfiguration = ''
        pki mail.example.com cert "${credsDir}/cert.pem"
        pki mail.example.com key "${credsDir}/key.pem"
        listen on localhost tls pki mail.example.com
        action act1 relay host smtp://127.0.0.1:10027
        match for local action act1
      '';
    };
}
```
