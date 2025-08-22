## Basic usage

A minimal configuration using Let’s Encrypt for TLS certificates looks like this:

```programlisting
{
  services.jitsi-meet = {
    enable = true;
    hostName = "jitsi.example.com";
  };
  services.jitsi-videobridge.openFirewall = true;
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  security.acme.email = "me@example.com";
  security.acme.acceptTerms = true;
}
```

Jitsi Meet depends on the Prosody XMPP server only for message passing from the web browser while the default Prosody configuration is intended for use with standalone XMPP clients and XMPP federation. If you only use Prosody as a backend for Jitsi Meet it is therefore recommended to also enable `services.jitsi-meet.prosody.lockdown` option to disable unnecessary Prosody features such as federation or the file proxy.
