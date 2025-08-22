## Configuration

Example configuration:

```programlisting
{
  services.pihole-web = {
    enable = true;
    ports = [ 80 ];
  };
}
```

The dashboard can be configured using [`services.pihole-ftl.settings`](options.html#opt-services.pihole-ftl.settings), in particular the `webserver` subsection.
