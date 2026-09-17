# Interface names

Hosts here boot with `net.ifnames=0`, so kernel names such as `eth0` and `wlan0` follow the order the kernel discovers the devices, which is not guaranteed across boots.
A host with two interfaces of the same class, or with a removable adapter, can see the numbering move between devices.
`modules/tpnix/networking.nix` pins that laptop's internal Wi-Fi card to `wifi0`, so a rule keyed to that name follows the card rather than a USB adapter that registered first.

songbird carries no pin: its two onboard NICs are read as `eth0` and `eth1` in kernel enumeration order, and no rule is keyed to a wired name.
Pin the device before adding one.
Link files follow the matching and apply rules in [Configure a systemd-udevd link policy](link-policy.md).

## Pin an interface name

A firewall rule keyed to a name applies to whatever device holds the name, and a removable adapter is absent on some boots by definition.
Pin the device with `linkConfig.Name` matched on its path, as `modules/tpnix/networking.nix` does for the internal Wi-Fi card:

```nix
systemd.network.links."10-wifi0" = {
  matchConfig.Path = "pci-0000:00:14.3";
  linkConfig = {
    Name = "wifi0";
    # The pin displaces 99-default.link for this device, so restore the
    # alternative names it would otherwise supply. Its "mac" token is left
    # out: that derives an altname from the factory hardware address.
    AlternativeNamesPolicy = "database onboard slot path";
  };
};
```

Read the value from `udevadm info -q property -p /sys/class/net/<name>`, field `ID_PATH`.
Matching on the path rather than `PermanentMACAddress` keeps a hardware address out of the repository.
It also degrades safely: when the device is removed or moved to another slot, nothing is named `wifi0`, so the firewall rule matches no device instead of landing on a different one.

Pin to a name outside the namespaces the kernel assigns itself: `eth*`, `wlan*`, `usb*` (the usbnet default for `cdc_ether` and `rndis_host`), `wwan*`, `ib*`, and `sl*`.
A rename into one of those can collide with a device that already holds it.

A pinned device gets no other `.link`.
udev applies only the first matching file, so a `10-*.link` pin also displaces systemd's `99-default.link` for that device, dropping its `NamePolicy`, `AlternativeNamesPolicy`, and `MACAddressPolicy=persistent` defaults, and a second `.link` added later for the same device is never read.
That is why the example above carries `AlternativeNamesPolicy` in the pin file.
One default must not come back: `systemd.link(5)` gives `Name=` lower precedence than `NamePolicy=`, so restoring `NamePolicy` would override the pin and hand the device back to whichever name the policy resolves, with no error.

The pins restore `AlternativeNamesPolicy` but not `MACAddressPolicy`, because NetworkManager owns the address on these hosts and a udev address policy would conflict with it.
They also drop the `mac` token that systemd's own default carries, because it derives an `enx<permanent-mac>` or `wlx<permanent-mac>` alternative name from the factory address, which is the value the `"stable"` policy exists to stop presenting.

## Narrow the alternative names without pinning a name

Dropping the `mac` token is a separate concern from pinning a name, and most devices here want only the first.
`net.ifnames=0` gates `NamePolicy=` alone: systemd's `enable_name_policy()` is read at one call site, the rename, while `link_generate_alternative_names()` is ungated.
So a device with no `.link` still gets the `mac` token from `99-default.link` and presents `enx<permanent-mac>`, even though nothing renames it.
Check a running host with `ip -d link show <name>`, or with `udevadm info -q property -p /sys/class/net/<name>` for the computed `ID_NET_NAME_MAC`.

The fix is a `.link` with a binding match and **no** `Name=`:

```nix
systemd.network.links."10-<device>" = {
  matchConfig.Path = "<ID_PATH value>";
  linkConfig = {
    # Safe here, unlike in a pin: there is no Name= for it to override. Under
    # net.ifnames=0 it is inert, and it keeps the device on the fleet scheme if
    # networking.usePredictableInterfaceNames is ever flipped.
    NamePolicy = "keep kernel database onboard slot path";
    AlternativeNamesPolicy = "database onboard slot path";
  };
};
```

This is the shape `modules/songbird/networking.nix` uses, and it renames nothing, so it is not a pin.
A broad, empty, globbed, or multi-valued match applies to every device no earlier file matched, renaming each of them if it carries a `Name=`.
udev merges `/etc/systemd/network` with `/usr/lib/systemd/network` by basename, and `99-default.link` matches every device, so a file whose basename sorts after it is never read.

Precedence is udev's `strcmp` order of the rendered `<name>.link` basenames, not of the attribute names.
`-` sorts before `.`, so `10-net-fallback.link` is read before `10-net.link` even though `10-net-fallback` sorts after `10-net`.

The two shapes invert the `NamePolicy` rule.
A pin must not carry it, because the policy would silently win over `Name=`.
A file without `Name=` carries it, because omitting it drops the default for a device that is not being renamed anyway.
