# Configure a systemd-udevd link policy

`systemd.network.links` writes `/etc/systemd/network/*.link`, and `systemd-udevd` honors those files whether or not `systemd-networkd` is enabled, so a link policy also takes effect on the NetworkManager hosts in this repository.
udev applies it when the device is initialized and NetworkManager overwrites the address again on activation, so set a `MACAddressPolicy` only for devices whose NetworkManager `macAddress` policy stays at `"preserve"` ([Choose a MAC address policy](README.md)).
That conflict is specific to the address: `linkConfig.Name` does not collide with NetworkManager, and [Interface names](interface-names.md) uses it to pin a name.

## Match one device

Always give the policy a `matchConfig`.
A `.link` file with no valid `[Match]` settings matches every interface udev initializes, and udev applies only the first matching file in lexicographic order.
An unmatched `10-wlan.link` therefore randomizes bridges, `veth` pairs, tunnels, and wired NICs as well, and shadows every higher-numbered `.link` file on the host.
The same first-match rule means a device already covered by a pin never reads a second file: tpnix's internal card matches `10-wifi0.link`, which sorts first, so a policy for that device belongs in the pin file.

Otherwise match on `Path`, which names a device.
`OriginalName` matches a name, and under `net.ifnames=0` that name follows discovery order rather than identifying hardware:

```nix
# A MACAddressPolicy only survives if NetworkManager is not also setting the
# address on this device, and the shared baseline sets "stable". This option is
# host-wide, not per-device: it drops "stable" on every Wi-Fi interface on the
# host, while the .link below reaches only the one it matches. Use it only where
# no Wi-Fi device should use the shared policy.
networking.networkmanager.wifi.macAddress = "preserve";

systemd.network.links."10-wlan" = {
  matchConfig.Path = "<ID_PATH of the intended adapter>";
  linkConfig = {
    MACAddressPolicy = "random";
    # 10-wlan.link sorts before 99-default.link, so it is the only .link udev
    # applies to this device. Restore the alternative names the default would
    # otherwise supply, minus its "mac" token.
    AlternativeNamesPolicy = "database onboard slot path";
  };
};
```

## Address policy values

The `.link` `MACAddressPolicy` values are `"persistent"`, `"random"`, and `"none"`:

- `"persistent"` keeps the address the kernel already uses when the hardware reports a persistent one, which is the normal case.
  It generates a deterministic address only for hardware without one, so it does not hide a factory address.
- `"random"` generates a new random address each time the device appears, unless the kernel already assigned a random one.
  The result always has the unicast and locally administered bits set.
- `"none"` keeps the address the kernel assigned, and is the only policy under which `MACAddress=` applies.
  Set `linkConfig.MACAddress` alongside it for a fixed explicit address.

## Apply a change

Apply link-policy changes before the device appears.
Rebooting, replugging a USB adapter, or otherwise reinitializing the link is more reliable than restarting a running network manager.
