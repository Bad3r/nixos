# Choose a MAC address policy

Use NetworkManager's MAC-address options for the interfaces this repository manages through NetworkManager.
The shared host module sets both Wi-Fi and Ethernet to `"stable"`, which gives each connection a hashed MAC address without exposing the device's permanent hardware address on every network.

Choose one component to own the MAC address for an interface.
Do not combine NetworkManager's `macAddress` options with a `.link` `MACAddressPolicy=` or `MACAddress=` ([link policy](link-policy.md)) for the same device: `systemd-udevd` applies the link setting when the device is initialized, then NetworkManager overwrites the address again when it activates a connection.
Only the address settings conflict: `linkConfig.Name` does not, so a device keeps the `"stable"` policy and can still carry a [pinned name](interface-names.md#pin-an-interface-name).

## Check the interface and its current address

This repository sets `networking.usePredictableInterfaceNames = false` in [`modules/hosts/common/networking.nix`](../../modules/hosts/common/networking.nix), so the kernel names interfaces `eth0`, `eth1`, `wlan0`, and so on rather than deriving `enp0s20f0u1u4`-style names from bus topology.
Those names follow discovery order, so a name that carries a firewall rule is pinned rather than observed, per [Interface names](interface-names.md).

```bash
nmcli device status
ip link show
cat /sys/class/net/wlan0/address   # address currently presented
ethtool -P wlan0                   # permanent hardware address
```

Read both.
Once a policy other than `"preserve"` or `"permanent"` is active, `/sys/class/net/*/address` reports the address NetworkManager assigned, not the factory one.
`ethtool -P` is what identifies the existing DHCP reservation or ACL entry being replaced.
NetworkManager exposes only the presented address, as `GENERAL.HWADDR` in `nmcli device show`; it has no permanent-address field.

Use the actual interface name in every example below.

## Configure NetworkManager policies

The repository's shared policy is in [`modules/hosts/common/networking.nix`](../../modules/hosts/common/networking.nix):

```nix
networking.networkmanager = {
  wifi.macAddress = lib.mkDefault "stable";
  ethernet.macAddress = lib.mkDefault "stable";
};
```

`lib.mkDefault` allows a host module to set a different policy.
To keep the shared policy, remove a host-specific assignment instead of setting it to `"preserve"`.

Set one or both options in the module that owns the host when the host needs a different behavior:

```nix
networking.networkmanager = {
  wifi.macAddress = "random";
  ethernet.macAddress = "random";
};
```

NetworkManager accepts these values for both Wi-Fi and Ethernet unless noted:

- `"permanent"` uses the device's factory MAC address.
- `"preserve"` leaves the address unchanged when the connection activates, and is the upstream default.
- `"random"` creates a new randomized address on every connection activation.
- `"stable"` creates a stable, hashed address for the connection, and is the repository default.
- `"stable-ssid"`, Wi-Fi only, creates a stable, hashed address per Wi-Fi network name.
- An explicit address such as `"02:00:00:00:00:01"` sets that address; use a valid, locally administered unicast address.

Use `"random"` when linkability across connection activations matters more than address continuity.
It creates a new address on every activation, so it breaks captive-portal state, DHCP reservations, and network allowlists repeatedly.
Use `"stable"` when those services need a predictable address without using the permanent hardware address, then [re-key them](stable-mac-rekey.md).

## Change the address temporarily with macchanger

Use `macchanger` for a one-off test instead of a persistent configuration.
Setting a hardware address needs `CAP_NET_ADMIN`, and the kernel rejects the change with `EBUSY` while the interface is still running.
Disconnecting the NetworkManager device is not enough on its own: that deactivates the connection but leaves a Wi-Fi interface up so it can keep scanning.
Release the device from NetworkManager and bring the link down first.

Resolve the package as the unprivileged user and elevate only the binary.
Running `nix run` under `sudo` re-evaluates the flake against root's registry, store, and caches instead:

```bash
macchanger=$(nix build --no-link --print-out-paths nixpkgs#macchanger)/bin/macchanger

nmcli device set wlan0 managed no
sudo ip link set dev wlan0 down
sudo "$macchanger" -r wlan0   # -r randomizes, -p restores the permanent address
sudo ip link set dev wlan0 up
```

Check the temporary result, then hand the device back to NetworkManager:

```bash
cat /sys/class/net/wlan0/address
ip link show dev wlan0
nmcli device set wlan0 managed yes
```

NetworkManager restores its configured address the next time it activates the connection, so `macchanger` is no substitute for a declarative NetworkManager or `.link` policy.

Changing a MAC address reduces one identifier exposed to a local network.
It does not prevent tracking through Wi-Fi network names, IP-level identifiers, browser fingerprints, or account activity.
