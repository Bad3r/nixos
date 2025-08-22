## Basic Usage

A minimal configuration looks like this:

```programlisting
{
  services.gns3-server = {
    enable = true;

    auth = {
      enable = true;
      user = "gns3";
      passwordFile = "/var/lib/secrets/gns3_password";
    };

    ssl = {
      enable = true;
      certFile = "/var/lib/gns3/ssl/cert.pem";
      keyFile = "/var/lib/gns3/ssl/key.pem";
    };

    dynamips.enable = true;
    ubridge.enable = true;
    vpcs.enable = true;
  };
}
```
