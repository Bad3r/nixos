## Using with other MTAs

Mailman also supports other MTA, though with a little bit more configuration. For example, to use Mailman with Exim, you can use the following settings:

```programlisting
{ config, ... }:
{
  services = {
    mailman = {
      enable = true;
      siteOwner = "mailman@example.org";
      enablePostfix = false;
      settings.mta = {
        incoming = "mailman.mta.exim4.LMTP";
        outgoing = "mailman.mta.deliver.deliver";
        lmtp_host = "localhost";
        lmtp_port = "8024";
        smtp_host = "localhost";
        smtp_port = "25";
        configuration = "python:mailman.config.exim4";
      };
    };
    exim = {
      enable = true;
      # You can configure Exim in a separate file to reduce configuration.nix clutter

      config = builtins.readFile ./exim.conf;
    };
  };
}
```

The exim config needs some special additions to work with Mailman. Currently NixOS can’t manage Exim config with such granularity. Please refer to [Mailman documentation](https://mailman.readthedocs.io/en/latest/src/mailman/docs/mta.html) for more info on configuring Mailman for working with Exim.
