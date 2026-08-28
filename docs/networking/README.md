# Choose a MAC address policy

Use NetworkManager's MAC-address options for the interfaces that this
repository manages through NetworkManager. The shared host module sets both
Wi-Fi and Ethernet to `"stable"`, which gives each connection a hashed MAC
address without exposing the device's permanent hardware address on every
network.

Choose one component to own the MAC address for an interface. Do not combine
NetworkManager's `macAddress` options with a `.link` `MACAddressPolicy=` or
`MACAddress=` for the same device: `systemd-udevd` applies the link setting
when the device is initialized, then NetworkManager overwrites the address
again when it activates a connection. Only the address settings conflict.
`linkConfig.Name` does not, and is used below to pin a name on a device whose
NetworkManager policy stays `"stable"`.

## Check the interface and its current address

This repository sets `networking.usePredictableInterfaceNames = false` in
[`modules/hosts/common/networking.nix`](../../modules/hosts/common/networking.nix),
so the kernel names interfaces `eth0`, `eth1`, `wlan0`, and so on rather than
deriving `enp0s20f0u1u4`-style names from bus topology.

Those names follow the order the kernel discovers the devices, which is not
guaranteed across boots. A host with two interfaces of the same class, or with
a removable adapter, can see the numbering move between devices. A name that
carries a firewall rule must therefore be pinned rather than observed: see
[Pin an interface name](#pin-an-interface-name). `modules/system76/networking.nix`
pins its USB ethernet adapter to `lan0` for that reason, so a rule keyed to that
name follows the adapter, and `modules/songbird/networking.nix` pins that
desktop's two onboard NICs to `lan0` and `lan1` by PCI path so their kernel
numbering cannot swap between boots. Every host currently leaves
`firewallDnsInterfaces` empty.

```bash
nmcli device status
ip link show
cat /sys/class/net/wlan0/address   # address currently presented
ethtool -P wlan0                   # permanent hardware address
```

Read both. Once a policy other than `"preserve"` or `"permanent"` is active,
`/sys/class/net/*/address` reports the address NetworkManager assigned, not the
factory one, so `ethtool -P` is what identifies the existing DHCP reservation
or ACL entry you are replacing. NetworkManager exposes only the presented
address, as `GENERAL.HWADDR` in `nmcli device show`; it has no permanent-address
field.

Use the actual interface name in every example below.

## Configure NetworkManager policies

The repository's shared policy is in
[`modules/hosts/common/networking.nix`](../../modules/hosts/common/networking.nix):

```nix
networking.networkmanager = {
  wifi.macAddress = lib.mkDefault "stable";
  ethernet.macAddress = lib.mkDefault "stable";
};
```

`lib.mkDefault` allows a host module to set a different policy. To keep the
shared policy, remove a host-specific assignment instead of setting it to
`"preserve"`.

Set one or both options in the module that owns the host when the host needs a
different behavior:

```nix
networking.networkmanager = {
  wifi.macAddress = "random";
  ethernet.macAddress = "random";
};
```

NetworkManager accepts these values:

| Value                 | Wi-Fi | Ethernet | Behavior                                                                                  |
| --------------------- | ----- | -------- | ----------------------------------------------------------------------------------------- |
| `"permanent"`         | Yes   | Yes      | Uses the device's factory MAC address.                                                    |
| `"preserve"`          | Yes   | Yes      | Leaves the address unchanged when the connection activates. This is the upstream default. |
| `"random"`            | Yes   | Yes      | Creates a new randomized address on every connection activation.                          |
| `"stable"`            | Yes   | Yes      | Creates a stable, hashed address for the connection. This is the repository default.      |
| `"stable-ssid"`       | Yes   | No       | Creates a stable, hashed address per Wi-Fi network name.                                  |
| `"02:00:00:00:00:01"` | Yes   | Yes      | Sets the specified address. Use a valid, locally administered unicast address.            |

Use `"random"` when linkability across connection activations matters more
than address continuity. It creates a new address on every activation, so it
breaks captive-portal state, DHCP reservations, and network allowlists
repeatedly. Use `"stable"` when those services need a predictable address
without using the permanent hardware address.

## Re-key services after moving a host to `"stable"`

`"stable"` is not the permanent hardware address either. NetworkManager hashes
the connection's `stable-id` with the machine identity held in
`/var/lib/NetworkManager/secret_key`; since secret-key version 2 that hash
covers `/etc/machine-id` as well. It also hashes in the interface name, and
this repository leaves `connection.stable-id` unset, so the stable-id falls
back to `default${CONNECTION}`, which is keyed on the profile's
`connection.uuid`. The generated address is therefore specific to one profile
on one interface on one host, and it changes whenever any of those inputs is
reseeded.

Moving a host off the upstream `"preserve"` default changes the address it
presents at the next activation. Re-key DHCP reservations, MAC allowlists, and
wired 802.1X MAB entries to the generated address after that cutover, and again
after any of these:

- Deleting and re-creating a connection profile, including "forget this
  network" followed by a rejoin, because the replacement profile gets a new
  `connection.uuid`. This is the trigger that fires in normal use.
- Renaming the interface, including a change to
  `networking.usePredictableInterfaceNames` or a kernel discovery order that
  moves a device between `eth0` and `eth1`. Clear or update any profile that
  pins `connection.interface-name` before the rename. `nm-settings-nmcli(5)`
  warns that "if interface names change or are reordered the connection may be
  applied to the wrong interface", and a profile that stops matching is
  replaced by an auto-generated one whose new UUID derives a different address
  again.
- Reinstalling the host, or anything else that regenerates
  `/var/lib/NetworkManager/secret_key` or `/etc/machine-id`.

Preserve both of those files when restoring a host from backup to keep the
generated addresses.

Read the addresses after rebooting, not after `nixos-rebuild switch`.
`usePredictableInterfaceNames` reaches the host as the `net.ifnames=0` kernel
parameter, so interfaces keep their old names until the next boot. An address
read before the rename is reseeded by it. The `.link` pins in
`modules/<host>/networking.nix` take effect at that boot too, so a name they
create matches no device until then, and anything keyed to it is inert for that
window.

Read one address per connection profile that carries a reservation or an ACL
entry, not one per host: each profile has its own UUID and therefore its own
derived address, so a host with several saved Wi-Fi networks presents a
different address on each. Activate the profile, then read what the device
presents for it. `nmcli device connect` would activate whichever profile
autoconnect picks rather than the one being re-keyed:

```bash
nmcli connection show                       # profile names
nmcli connection up "<profile name>"
nmcli -f GENERAL.HWADDR device show wlan0
```

## Configure a systemd-udevd link policy

`systemd.network.links` writes `/etc/systemd/network/*.link`, and
`systemd-udevd` honors those files whether or not `systemd-networkd` is
enabled, so a link policy also takes effect on the NetworkManager hosts in this
repository. udev applies it when the device is initialized and NetworkManager
overwrites the address again on activation, so set a `MACAddressPolicy` only
for devices whose NetworkManager `macAddress` policy you left at `"preserve"`.
That conflict is specific to the address. `linkConfig.Name` does not collide
with NetworkManager and is used below to pin an interface name.

Always give the policy a `matchConfig`. A `.link` file with no valid `[Match]`
settings matches every interface udev initializes, and udev applies only the
first matching file in lexicographic order, so an unmatched `10-wlan.link`
randomizes bridges, `veth` pairs, tunnels, and wired NICs as well, and shadows
every higher-numbered `.link` file on the host. That same first-match rule means
a device already covered by a pin never reads a second file: tpnix's internal
card matches `10-wifi0.link`, which sorts first, so a policy for that device
belongs in the pin file rather than in a separate one. Otherwise match on `Path`,
which names a device. `OriginalName` matches a name, and under `net.ifnames=0`
that name follows discovery order rather than identifying hardware:

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

The `.link` `MACAddressPolicy` values are `"persistent"`, `"random"`, and
`"none"`:

- `"persistent"` keeps the address the kernel already uses when the hardware
  reports a persistent one, which is the normal case. It generates a
  deterministic address only for hardware without one, so it does not hide a
  factory address.
- `"random"` generates a new random address each time the device appears,
  unless the kernel already assigned a random one. The result always has the
  unicast and locally administered bits set.
- `"none"` keeps the address the kernel assigned, and is the only policy under
  which `MACAddress=` applies.

### Pin an interface name

Kernel names follow discovery order, so a name is not tied to one device. That
matters when a name carries a firewall rule: `firewallDnsInterfaces` opens UDP
53/67 and TCP 53 on whatever device holds the name, and a removable adapter is
absent on some boots by definition. Pin the device with `linkConfig.Name`
matched on its path, as `modules/system76/networking.nix` does for the USB
ethernet adapter, so a rule later keyed to that name follows the adapter:

```nix
systemd.network.links."10-lan0" = {
  matchConfig.Path = "pci-0000:00:14.0-usb-0:1.4:1.0";
  linkConfig = {
    Name = "lan0";
    # The pin displaces 99-default.link for this device, so restore the
    # alternative names it would otherwise supply. Its "mac" token is left
    # out: that derives an altname from the factory hardware address.
    AlternativeNamesPolicy = "database onboard slot path";
  };
};
```

Read the value from `udevadm info -q property -p /sys/class/net/<name>`, field
`ID_PATH`. Matching on the path rather than `PermanentMACAddress` keeps a
hardware address out of the repository, and it degrades safely: when the
adapter is detached or moved to another port, nothing is named `lan0`, so the
firewall rule matches no device instead of landing on a different one.

Pin to a name outside the namespaces the kernel assigns itself: `eth*`,
`wlan*`, `usb*` (the usbnet default for `cdc_ether` and `rndis_host`), `wwan*`,
`ib*`, and `sl*`. A rename into one of those can collide with a device that
already holds it. `modules/hosts/common/firewall.nix` treats exactly that set
as kernel-assigned.

A pinned device gets no other `.link`. udev applies only the first matching
file, so a `10-*.link` pin also displaces systemd's `99-default.link` for that
device, dropping its `NamePolicy`, `AlternativeNamesPolicy`, and
`MACAddressPolicy=persistent` defaults, and a second `.link` added later for the
same device is never read, which is why the example above carries
`AlternativeNamesPolicy` in the pin file. One default must not come back:
`NamePolicy`. Per `systemd.link(5)`, `Name=` "has lower precedence than
`NamePolicy=`", so restoring it would override the pin and hand the device back
to whichever name the policy resolves, with no error.

The pins in this repository restore `AlternativeNamesPolicy` but deliberately
not `MACAddressPolicy`: NetworkManager owns the address on these hosts, so
setting a udev address policy here would be the conflict this page opens with.
They also drop the `mac` token that systemd's own default carries, because it
derives an `enx<permanent-mac>` or `wlx<permanent-mac>` alternative name from
the factory address, which is the value the `"stable"` policy exists to stop
presenting.

Apply link-policy changes before the device appears. Rebooting, replugging a
USB adapter, or otherwise reinitializing the link is more reliable than
restarting a running network manager. Set `linkConfig.MACAddress` when you need
a fixed explicit address, alongside the `"none"` policy above.

## Change the address temporarily with macchanger

Use `macchanger` for a one-off test instead of a persistent configuration.
Setting a hardware address needs `CAP_NET_ADMIN`, and the kernel rejects the
change with `EBUSY` while the interface is still running. Disconnecting the
NetworkManager device is not enough on its own: that deactivates the
connection but leaves a Wi-Fi interface up so it can keep scanning. Release
the device from NetworkManager and bring the link down first.

Resolve the package as your own user and elevate only the binary. Running
`nix run` under `sudo` re-evaluates the flake against root's registry, store,
and caches instead:

```bash
macchanger=$(nix build --no-link --print-out-paths nixpkgs#macchanger)/bin/macchanger

nmcli device set wlan0 managed no
sudo ip link set dev wlan0 down
sudo "$macchanger" -r wlan0   # -r randomizes, -p restores the permanent address
sudo ip link set dev wlan0 up
```

Verify the temporary result, then hand the device back to NetworkManager:

```bash
cat /sys/class/net/wlan0/address
ip link show dev wlan0
nmcli device set wlan0 managed yes
```

NetworkManager restores its configured address the next time it activates the
connection, so do not use `macchanger` as a substitute for a declarative
NetworkManager or `.link` policy.

Changing a MAC address reduces one identifier exposed to a local network. It
does not prevent tracking through Wi-Fi network names, IP-level identifiers,
browser fingerprints, or account activity.
