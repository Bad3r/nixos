## Basic Usage

A minimal configuration looks like this:

```programlisting
{
  services.ocsinventory-agent = {
    enable = true;
    settings = {
      server = "https://ocsinventory.localhost:8080/ocsinventory";
      tag = "01234567890123";
    };
  };
}
```

This configuration will periodically run the ocsinventory-agent SystemD service.

The OCS Inventory Agent will inventory the computer and then sends the results to the specified OCS Inventory Server.
