## Configuring

Samba configuration is located in the `/etc/samba/smb.conf` file.

### File share

This configuration will configure Samba to serve a `public` file share which is read-only and accessible without authentication:

```programlisting
{
  services.samba = {
    enable = true;
    settings = {
      "public" = {
        "path" = "/public";
        "read only" = "yes";
        "browseable" = "yes";
        "guest ok" = "yes";
        "comment" = "Public samba share.";
      };
    };
  };
}
```
