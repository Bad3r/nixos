## Service Configuration

A basic config that notifies you of all certificate changes for your domain would look as follows:

```programlisting
{
  services.certspotter = {
    enable = true;
    # replace example.org with your domain name

    watchlist = [ ".example.org" ];
    emailRecipients = [ "webmaster@example.org" ];
  };

  # Configure an SMTP client

  programs.msmtp.enable = true;
  # Or you can use any other module that provides sendmail, like

  # services.nullmailer, services.opensmtpd, services.postfix

}
```

In this case, the leading dot in `".example.org"` means that Cert Spotter should monitor not only `example.org`, but also all of its subdomains.
