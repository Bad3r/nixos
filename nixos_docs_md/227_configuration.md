## Configuration

As an example config file using Cloudflare as DoT upstream, you can use this [crab-hole.toml](https://github.com/LuckyTurtleDev/crab-hole/blob/main/example-config.toml)

The following is a basic nix config using UDP as a downstream and Cloudflare as upstream.

```programlisting
{
  services.crab-hole = {
    enable = true;

    settings = {
      blocklist = {
        include_subdomains = true;
        lists = [
          "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts"
          "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
        ];
      };

      downstream = [
        {
          protocol = "udp";
          listen = "127.0.0.1";
          port = 53;
        }
        {
          protocol = "udp";
          listen = "::1";
          port = 53;
        }
      ];

      upstream = {
        name_servers = [
          {
            socket_addr = "1.1.1.1:853";
            protocol = "tls";
            tls_dns_name = "1dot1dot1dot1.cloudflare-dns.com";
            trust_nx_responses = false;
          }
          {
            socket_addr = "[2606:4700:4700::1111]:853";
            protocol = "tls";
            tls_dns_name = "1dot1dot1dot1.cloudflare-dns.com";
            trust_nx_responses = false;
          }
        ];
      };
    };
  };
}
```

To test your setup, just query the DNS server with any domain like `example.com`. To test if a domain gets blocked, just choose one of the domains from the blocklist. If the server does not return an IP, this worked correctly.

### Downstream options

There are multiple protocols which are supported for the downstream: UDP, TLS, HTTPS and QUIC. Below you can find a brief overview over the various protocol options together with an example for each protocol.

#### UDP

UDP is the simplest downstream, but it is not encrypted. If you want encryption, you need to use another protocol. **\*Note:** This also opens a TCP port\*

```programlisting
{
  services.crab-hole.settings.downstream = [
    {
      protocol = "udp";
      listen = "localhost";
      port = 53;
    }
  ];
}
```

#### TLS

TLS is a simple encrypted options to serve DNS. It comes with similar settings to UDP, but you additionally need a valid TLS certificate and its private key. The later are specified via a path to the files. A valid TLS certificate and private key can be obtained using services like ACME. Make sure the crab-hole service user has access to these files. Additionally you can set an optional timeout value.

```programlisting
{
  services.crab-hole.settings.downstream = [
    {
      protocol = "tls";
      listen = "[::]";
      port = 853;
      certificate = ./dns.example.com.crt;
      key = "/dns.example.com.key";
      # optional (default = 3000)

      timeout_ms = 3000;
    }
  ];
}
```

#### HTTPS

HTTPS has similar settings to TLS, with the only difference being the additional `dns_hostname` option. This protocol might need a reverse proxy if other HTTPS services are to share the same port. Make sure the service has permissions to access the certificate and key.

**\*Note:** this config is untested\*

```programlisting
{
  services.crab-hole.settings.downstream = [
    {
      protocol = "https";
      listen = "[::]";
      port = 443;
      certificate = ./dns.example.com.crt;
      key = "/dns.example.com.key";
      # optional

      dns_hostname = "dns.example.com";
      # optional (default = 3000)

      timeout_ms = 3000;
    }
  ];
}
```

#### QUIC

QUIC has identical settings to the HTTPS protocol. Since by default it doesn’t run on the standard HTTPS port, you shouldn’t need a reverse proxy. Make sure the service has permissions to access the certificate and key.

```programlisting
{
  services.crab-hole.settings.downstream = [
    {
      protocol = "quic";
      listen = "127.0.0.1";
      port = 853;
      certificate = ./dns.example.com.crt;
      key = "/dns.example.com.key";
      # optional

      dns_hostname = "dns.example.com";
      # optional (default = 3000)

      timeout_ms = 3000;
    }
  ];
}
```

### Upstream options

You can set additional options of the underlying DNS server. A full list of all the options can be found in the [hickory-dns documentation](https://docs.rs/trust-dns-resolver/0.23.0/trust_dns_resolver/config/struct.ResolverOpts.html).

This can look like the following example.

```programlisting
{
  services.crab-hole.settings.upstream.options = {
    validate = false;
  };
}
```

#### DNSSEC Issues

Due to an upstream issue of [hickory-dns](https://github.com/hickory-dns/hickory-dns/issues/2429), sites without DNSSEC will not be resolved if `validate = true`. Only DNSSEC capable sites will be resolved with this setting. To prevent this, set `validate = false` or omit the `[upstream.options]`.

### API

The API allows a user to fetch statistic and information about the crab-hole instance. Basic information is available for everyone, while more detailed information is secured by a key, which will be set with the `admin_key` option.

```programlisting
{
  services.crab-hole.settings.api = {
    listen = "127.0.0.1";
    port = 8080;
    # optional (default = false)

    show_doc = true; # OpenAPI doc loads content from third party websites

    # optional

    admin_key = "1234";
  };
}
```

The documentation can be enabled separately for the instance with `show_doc`. This will then create an additional webserver, which hosts the API documentation. An additional resource is in work in the [crab-hole repository](https://github.com/LuckyTurtleDev/crab-hole).
