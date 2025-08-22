## Configuration

By default, the module will execute Pingvin Share backend and frontend on the ports 8080 and 3000.

I will run two systemd services named `pingvin-share-backend` and `pingvin-share-frontend` in the specified data directory.

Here is a basic configuration:

```programlisting
{
  services-pingvin-share = {
    enable = true;

    openFirewall = true;

    backend.port = 9010;
    frontend.port = 9011;
  };
}
```
