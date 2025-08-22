## Troubleshooting

You can check for errors using `systemctl status crab-hole` or `journalctl -xeu crab-hole.service`.

### Invalid config

Some options of the service are in freeform and not type checked. This can lead to a config which is not valid or cannot be parsed by crab-hole. The error message will tell you what config value could not be parsed. For more information check the [example config](https://github.com/LuckyTurtleDev/crab-hole/blob/main/example-config.toml).

### Permission Error

It can happen that the created certificates for TLS, HTTPS or QUIC are owned by another user or group. For ACME for example this would be `acme:acme`. To give the crab-hole service access to these files, the group which owns the certificate can be added as a supplementary group to the service. For ACME for example:

```programlisting
{ services.crab-hole.supplementaryGroups = [ "acme" ]; }
```
