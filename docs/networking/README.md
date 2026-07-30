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

Identify the interface name before changing a policy. Wireless interfaces are
often named `wlan0` or `wlp*`, while wired interfaces are often named `enp*`.

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
covers `/etc/machine-id` as well. Moving a host off the upstream `"preserve"`
default therefore changes the address it presents, once, at the next
activation.

Re-key DHCP reservations, MAC allowlists, and wired 802.1X MAB entries to the
generated address after the cutover. Re-key them again after a reinstall or
any operation that regenerates `/var/lib/NetworkManager/secret_key` or
`/etc/machine-id`, because both reseed the hash. Preserve those two files when
restoring a host from backup to keep the generated addresses.

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
A random policy can be written directly as:

```nix
systemd.network.links."10-wlan".linkConfig.MACAddressPolicy = "random";
```

Match the policy to the intended interface in a complete configuration. Match
`OriginalName` so a policy does not accidentally apply to another wireless
adapter:

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
