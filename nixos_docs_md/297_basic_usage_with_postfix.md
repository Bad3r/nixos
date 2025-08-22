## Basic usage with Postfix

For a basic configuration with Postfix as the MTA, the following settings are suggested:

```programlisting
{ config, ... }:
{
  services.postfix = {
    enable = true;
    settings.main = {
      transport_maps = [ "hash:/var/lib/mailman/data/postfix_lmtp" ];
      local_recipient_maps = [ "hash:/var/lib/mailman/data/postfix_lmtp" ];
      relay_domains = [ "hash:/var/lib/mailman/data/postfix_domains" ];
      smtpd_tls_chain_files = [
        (config.security.acme.certs."lists.example.org".directory + "/full.pem")
        (config.security.acme.certs."lists.example.org".directory + "/key.pem")
      ];
    };
  };
  services.mailman = {
    enable = true;
    serve.enable = true;
    hyperkitty.enable = true;
    webHosts = [ "lists.example.org" ];
    siteOwner = "mailman@example.org";
  };
  services.nginx.virtualHosts."lists.example.org".enableACME = true;
  networking.firewall.allowedTCPPorts = [
    25
    80
    443
  ];
}
```

DNS records will also be required:

- `AAAA` and `A` records pointing to the host in question, in order for browsers to be able to discover the address of the web server;

- An `MX` record pointing to a domain name at which the host is reachable, in order for other mail servers to be able to deliver emails to the mailing lists it hosts.

After this has been done and appropriate DNS records have been set up, the Postorius mailing list manager and the Hyperkitty archive browser will be available at https://lists.example.org/. Note that this setup is not sufficient to deliver emails to most email providers nor to avoid spam – a number of additional measures for authenticating incoming and outgoing mails, such as SPF, DMARC and DKIM are necessary, but outside the scope of the Mailman module.
