# Running WARP CLI commands

Use these commands after the host has been deployed with
`programs.cloudflare-warp.extended.enable = true`. The module installs the
headless WARP package, so `warp-cli`, `warp-svc`, `warp-dex`, and `warp-diag`
are available on enrolled hosts.

## Check runtime state

```bash
systemctl status cloudflare-warp.service
systemctl status cloudflare-warp-connect.service
ls -l /var/lib/cloudflare-warp/mdm.xml
warp-cli registration show
warp-cli status
warp-cli settings
warp-cli tunnel stats
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^warp='
```

A healthy full-mode deployment shows the daemon running, the connect oneshot as
`active (exited)`, a `0600 root:root` `mdm.xml`, an enrolled Zero Trust
registration, `warp-cli status` as connected, and `warp=on` in the Cloudflare
trace output.

## Control the tunnel

```bash
warp-cli --accept-tos connect
warp-cli --accept-tos disconnect
warp-cli status
```

`disconnect` is temporary when the managed `mdm.xml` allows it. If
`switch_locked` is true, the client prevents local disconnects.

## Inspect managed settings

```bash
warp-cli settings
warp-cli registration show
warp-cli tunnel stats
```

`mdm.xml` is authoritative for `service_mode`. Do not use `warp-cli mode` for
durable mode changes on a managed host. Change
`programs.cloudflare-warp.extended.serviceMode` and rebuild instead.

## Collect diagnostics

```bash
sudo warp-diag
sudo warp-diag feedback
journalctl -u cloudflare-warp.service -b
journalctl -u cloudflare-warp-connect.service -b
```

The diagnostics bundle includes client settings, status, and daemon logs. Search
the daemon log for `error`, `failed`, and `DNS connectivity check` to separate
DNS setup problems from tunnel problems.

## References

- [Troubleshooting WARP](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/troubleshooting/)
- [WARP diagnostic logs](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/troubleshooting/warp-diag/)
- [Firewall and network ports](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/deployment/firewall/)
