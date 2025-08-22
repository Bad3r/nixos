## Usage

To enable a Kerberos server:

```programlisting
{
  security.krb5 = {
    # Here you can choose between the MIT and Heimdal implementations.

    package = pkgs.krb5;
    # package = pkgs.heimdal;

    # Optionally set up a client on the same machine as the server

    enable = true;
    settings = {
      libdefaults.default_realm = "EXAMPLE.COM";
      realms."EXAMPLE.COM" = {
        kdc = "kerberos.example.com";
        admin_server = "kerberos.example.com";
      };
    };
  };

  services.kerberos-server = {
    enable = true;
    settings = {
      realms."EXAMPLE.COM" = {
        acl = [
          {
            principal = "adminuser";
            access = [
              "add"
              "cpw"
            ];
          }
        ];
      };
    };
  };
}
```
