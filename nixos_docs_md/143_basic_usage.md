## Basic usage

A minimal configuration looks like this:

```programlisting
{
  services.honk = {
    enable = true;
    host = "0.0.0.0";
    port = 8080;
    username = "username";
    passwordFile = "/etc/honk/password.txt";
    servername = "honk.example.com";
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
```
