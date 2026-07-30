# Choose a MAC address policy

Use NetworkManager's MAC-address options for the interfaces that this
repository manages through NetworkManager. The shared host module sets both
Wi-Fi and Ethernet to `"stable"`, which gives each connection a hashed MAC
address without exposing the device's permanent hardware address on every
network.

Choose one component to own the MAC address for an interface. Do not combine
NetworkManager's `macAddress` options with a `.link` policy for the same
device: `systemd-udevd` applies the link policy when the device is
initialized, then NetworkManager overwrites the address again when it
activates a connection.

## Check the interface and its current address

This repository sets `networking.usePredictableInterfaceNames = false` in
[`modules/hosts/common/networking.nix`](../../modules/hosts/common/networking.nix),
so the kernel names interfaces `eth0`, `eth1`, `wlan0`, and so on rather than
deriving `enp0s20f0u1u4`-style names from bus topology.

Those names follow the order the kernel discovers the devices, which is not
guaranteed across boots. A host with two interfaces of the same class can see
the numbering swap, so confirm the mapping before relying on a name in a
firewall rule or a link policy. Per-host interface values live in
`modules/<host>/policy.nix` and record the order observed at the time.

```bash
nmcli device status
ip link show
cat /sys/class/net/wlan0/address
```

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
  moves a device between `eth0` and `eth1`.
- Reinstalling the host, or anything else that regenerates
  `/var/lib/NetworkManager/secret_key` or `/etc/machine-id`.

Preserve both of those files when restoring a host from backup to keep the
generated addresses.

After rebuilding the host, reconnect the device and read the address to re-key
against:

```bash
nmcli device disconnect wlan0
nmcli device connect wlan0
cat /sys/class/net/wlan0/address
```

## Configure a systemd-udevd link policy

`systemd.network.links` writes `/etc/systemd/network/*.link`, and
`systemd-udevd` honors those files whether or not `systemd-networkd` is
enabled, so a link policy also takes effect on the NetworkManager hosts in this
repository. udev applies it when the device is initialized and NetworkManager
overwrites the address again on activation, so set a link policy only for
devices whose NetworkManager `macAddress` policy you left at `"preserve"`.

Always give the policy a `matchConfig`. A `.link` file with no valid `[Match]`
settings matches every interface udev initializes, and udev applies only the
first matching file in lexicographic order, so an unmatched `10-wlan.link`
randomizes bridges, `veth` pairs, tunnels, and wired NICs as well, and shadows
every higher-numbered `.link` file on the host. Match `OriginalName` so the
policy reaches only the intended adapter:

```nix
systemd.network.links."10-wlan" = {
  matchConfig.OriginalName = "wlan0";
  linkConfig.MACAddressPolicy = "random";
};
```

The `.link` `MACAddressPolicy` values are `"persistent"`, `"random"`, and
`"none"`:

- `"persistent"` creates a deterministic address for the link.
- `"random"` creates a new random address when the link is initialized.
- `"none"` leaves MAC-address policy disabled.

Apply link-policy changes before the device appears. Rebooting, replugging a
USB adapter, or otherwise reinitializing the link is more reliable than
restarting a running network manager. Set `linkConfig.MACAddress` when you need
a fixed explicit address, and leave `MACAddressPolicy` unset or `"none"`:
systemd ignores `MACAddress` while a policy is in effect.

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
