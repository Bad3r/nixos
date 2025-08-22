## Basic usage

A very minimal setup which reads incoming reports from an external email address and saves them to a local Elasticsearch instance looks like this:

```programlisting
{
  services.parsedmarc = {
    enable = true;
    settings.imap = {
      host = "imap.example.com";
      user = "alice@example.com";
      password = "/path/to/imap_password_file";
    };
    provision.geoIp = false; # Not recommended!

  };
}
```

Note that GeoIP provisioning is disabled in the example for simplicity, but should be turned on for fully functional reports.
