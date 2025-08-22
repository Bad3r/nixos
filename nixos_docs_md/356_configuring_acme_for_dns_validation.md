## Configuring ACME for DNS validation

This is useful if you want to generate a wildcard certificate, since ACME servers will only hand out wildcard certs over DNS validation. There are a number of supported DNS providers and servers you can utilise, see the [lego docs](https://go-acme.github.io/lego/dns/) for provider/server specific configuration values. For the sake of these docs, we will provide a fully self-hosted example using bind.

```programlisting
{
  services.bind = {
    enable = true;
    extraConfig = ''
      include "/var/lib/secrets/dnskeys.conf";
    '';
    zones = [
      rec {
        name = "example.com";
        file = "/var/db/bind/${name}";
        master = true;
        extraConfig = "allow-update { key rfc2136key.example.com.; };";
      }
    ];
  };

  # Now we can configure ACME

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "admin+acme@example.com";
  security.acme.certs."example.com" = {
    domain = "*.example.com";
    dnsProvider = "rfc2136";
    environmentFile = "/var/lib/secrets/certs.secret";
    # We don't need to wait for propagation since this is a local DNS server

    dnsPropagationCheck = false;
  };
}
```

The `dnskeys.conf` and `certs.secret` must be kept secure and thus you should not keep their contents in your Nix config. Instead, generate them one time with a systemd service:

```programlisting
{
  systemd.services.dns-rfc2136-conf = {
    requiredBy = [
      "acme-example.com.service"
      "bind.service"
    ];
    before = [
      "acme-example.com.service"
      "bind.service"
    ];
    unitConfig = {
      ConditionPathExists = "!/var/lib/secrets/dnskeys.conf";
    };
    serviceConfig = {
      Type = "oneshot";
      UMask = 77;
    };
    path = [ pkgs.bind ];
    script = ''
      mkdir -p /var/lib/secrets
      chmod 755 /var/lib/secrets
      tsig-keygen rfc2136key.example.com > /var/lib/secrets/dnskeys.conf
      chown named:root /var/lib/secrets/dnskeys.conf
      chmod 400 /var/lib/secrets/dnskeys.conf

      # extract secret value from the dnskeys.conf

      while read x y; do if [ "$x" = "secret" ]; then secret="''${y:1:''${#y}-3}"; fi; done < /var/lib/secrets/dnskeys.conf

      cat > /var/lib/secrets/certs.secret << EOF
      RFC2136_NAMESERVER='127.0.0.1:53'
      RFC2136_TSIG_ALGORITHM='hmac-sha256.'
      RFC2136_TSIG_KEY='rfc2136key.example.com'
      RFC2136_TSIG_SECRET='$secret'
      EOF
      chmod 400 /var/lib/secrets/certs.secret
    '';
  };
}
```

Now you’re all set to generate certs! You should monitor the first invocation by running `systemctl start acme-example.com.service & journalctl -fu acme-example.com.service` and watching its log output.
