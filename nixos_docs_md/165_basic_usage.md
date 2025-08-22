## Basic Usage

At first, an application secret is needed, this can be generated with:

```programlisting
$ cat /dev/urandom | tr -dc a-zA-Z0-9 | fold -w 48 | head -n 1
```

After that, `davis` can be deployed like this:

```programlisting
{
  services.davis = {
    enable = true;
    hostname = "davis.example.com";
    mail = {
      dsn = "smtp://username@example.com:25";
      inviteFromAddress = "davis@example.com";
    };
    adminLogin = "admin";
    adminPasswordFile = "/run/secrets/davis-admin-password";
    appSecretFile = "/run/secrets/davis-app-secret";
  };
}
```

This deploys Davis using a sqlite database running out of `/var/lib/davis`.

Logs can be found in `/var/lib/davis/var/log/`.
