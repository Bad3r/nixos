## Local mail

Instead of watching an external inbox, a local inbox can be automatically provisioned. The recipient’s name is by default set to `dmarc`, but can be configured in [services.parsedmarc.provision.localMail.recipientName](options.html#opt-services.parsedmarc.provision.localMail.recipientName). You need to add an MX record pointing to the host. More concretely: for the example to work, an MX record needs to be set up for `monitoring.example.com` and the complete email address that should be configured in the domain’s dmarc policy is `dmarc@monitoring.example.com`.

```programlisting
{
  services.parsedmarc = {
    enable = true;
    provision = {
      localMail = {
        enable = true;
        hostname = monitoring.example.com;
      };
      geoIp = false; # Not recommended!

    };
  };
}
```
