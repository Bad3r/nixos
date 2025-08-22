## Basic Usage

At first, a secret key is needed to be generated. This can be done with e.g.

```programlisting
$ openssl rand -base64 64
```

After that, `plausible` can be deployed like this:

```programlisting
{
  services.plausible = {
    enable = true;
    server = {
      baseUrl = "http://analytics.example.org";
      # secretKeybaseFile is a path to the file which contains the secret generated

      # with openssl as described above.

      secretKeybaseFile = "/run/secrets/plausible-secret-key-base";
    };
  };
}
```
