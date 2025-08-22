## Email

In addition to the basic setup, you’ll want to configure an SMTP server Discourse can use to send user registration and password reset emails, among others. You can also optionally let Discourse receive email, which enables people to reply to threads and conversations via email.

A basic setup which assumes you want to use your configured [hostname](options.html#opt-services.discourse.hostname) as email domain can be done like this:

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
    mail.outgoing = {
      serverAddress = "smtp.emailprovider.com";
      port = 587;
      username = "user@emailprovider.com";
      passwordFile = "/path/to/smtp_password_file";
    };
    mail.incoming.enable = true;
    secretKeyBaseFile = "/path/to/secret_key_base_file";
  };
}
```

This assumes you have set up an MX record for the address you’ve set in [hostname](options.html#opt-services.discourse.hostname) and requires proper SPF, DKIM and DMARC configuration to be done for the domain you’re sending from, in order for email to be reliably delivered.

If you want to use a different domain for your outgoing email (for example `example.com` instead of `discourse.example.com`) you should set [`services.discourse.mail.notificationEmailAddress`](options.html#opt-services.discourse.mail.notificationEmailAddress) and [`services.discourse.mail.contactEmailAddress`](options.html#opt-services.discourse.mail.contactEmailAddress) manually.

### Note

Setup of TLS for incoming email is currently only configured automatically when a regular TLS certificate is used, i.e. when [`services.discourse.sslCertificate`](options.html#opt-services.discourse.sslCertificate) and [`services.discourse.sslCertificateKey`](options.html#opt-services.discourse.sslCertificateKey) are set.
