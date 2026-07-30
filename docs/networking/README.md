# Choose a MAC address policy

Use NetworkManager's MAC-address options for the interfaces that this
repository manages through NetworkManager. The shared host module sets both
Wi-Fi and Ethernet to `"stable"`, which gives each connection a hashed MAC
address without exposing the device's permanent hardware address on every
network.

Choose one component to own the MAC address for an interface. Do not combine
NetworkManager's `macAddress` options with a `systemd-networkd` link policy for
the same device. NetworkManager can set the address again when it activates a
connection.

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
than address continuity. It can break captive-portal state, DHCP reservations,
or network allowlists. Use `"stable"` when those services need a predictable
address without using the permanent hardware address.

After rebuilding the host, reconnect the device and verify the active address:

```bash
nmcli device disconnect wlan0
nmcli device connect wlan0
cat /sys/class/net/wlan0/address
```

## Configure a systemd-networkd link policy

Use a `systemd.network.links` policy when `systemd-networkd` owns the link.
The requested random policy can be written directly as:

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
restarting a running network manager. Set `linkConfig.MACAddress` instead when
you need a fixed explicit address.

## Change the address temporarily with macchanger

Use `macchanger` for a one-off test instead of a persistent configuration.
Run it from a shell with `CAP_NET_ADMIN`, normally a root shell or through
`sudo`. Disconnect an active NetworkManager device first because changing its
address interrupts the connection.

```bash
nmcli device disconnect wlan0
nix run nixpkgs#macchanger -- -r wlan0   # random
nix run nixpkgs#macchanger -- -p wlan0   # restore permanent
```

If the shell does not have the required privilege, prefix the `nix run`
command with `sudo`. NetworkManager can restore its configured address the
next time it activates the connection, so do not use `macchanger` as a
substitute for a declarative NetworkManager or networkd policy.

Verify the temporary result before reconnecting:

```bash
cat /sys/class/net/wlan0/address
ip link show dev wlan0
```

Changing a MAC address reduces one identifier exposed to a local network. It
does not prevent tracking through Wi-Fi network names, IP-level identifiers,
browser fingerprints, or account activity.
