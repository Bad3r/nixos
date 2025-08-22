## Configuration

Here is the minimal configuration with additional configurations:

```programlisting
{
  services.jitsi-meet = {
    enable = true;
    hostName = "jitsi.example.com";
    prosody.lockdown = true;
    config = {
      enableWelcomePage = false;
      prejoinPageEnabled = true;
      defaultLang = "fi";
    };
    interfaceConfig = {
      SHOW_JITSI_WATERMARK = false;
      SHOW_WATERMARK_FOR_GUESTS = false;
    };
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
