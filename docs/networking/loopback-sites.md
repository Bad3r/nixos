# Loopback sites

`networking.loopbackSites` gives a local web UI a name such as `http://activitywatch.internal` with no port in the URL.
The option lives in [the shared module](../../modules/hosts/common/loopback-sites.nix).
Each entry adds the name to `/etc/hosts` on `127.0.0.1` and an nginx virtual host on loopback port 80 that proxies to the entry's upstream.
nginx runs only on hosts with at least one entry.

## Add a site

Set the entry in the app module that owns the service, keyed by the name:

```nix
networking.loopbackSites."example.internal".upstream = "http://127.0.0.1:8080";
```

Use a `.internal` name.
mDNS answers `.local` names first and never reads `/etc/hosts` on a miss.

## Host header

nginx passes the requested name upstream by default.
An upstream that accepts only its own address, as `aw-server` does while it binds loopback, sets `hostHeader` to that address.
nginx closes requests for any name without an entry, so a DNS-rebinding page never reaches an upstream through a rewritten header.

## Check a site

```bash
getent hosts example.internal
curl -sI http://example.internal/
systemctl status nginx.service
```
