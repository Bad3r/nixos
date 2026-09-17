# Re-key services after moving a host to `"stable"`

`"stable"` is not the permanent hardware address either.
NetworkManager hashes the connection's `stable-id` with the machine identity held in `/var/lib/NetworkManager/secret_key`; since secret-key version 2 that hash covers `/etc/machine-id` as well.
It also hashes in the interface name, and this repository leaves `connection.stable-id` unset, so the stable-id falls back to `default${CONNECTION}`, which is keyed on the profile's `connection.uuid`.
The generated address is therefore specific to one profile on one interface on one host, and it changes whenever any of those inputs is reseeded.

The policy itself is in [Choose a MAC address policy](README.md).

## When to re-key

Moving a host off the upstream `"preserve"` default changes the address it presents at the next activation.
Re-key DHCP reservations, MAC allowlists, and wired 802.1X MAB entries to the generated address after that cutover, and again after any of these:

- Deleting and re-creating a connection profile, including "forget this network" followed by a rejoin, because the replacement profile gets a new `connection.uuid`.
  This is the trigger that fires in normal use.
- Renaming the interface, including a change to `networking.usePredictableInterfaceNames` or a kernel discovery order that moves a device between `eth0` and `eth1`.
  Clear or update any profile that pins `connection.interface-name` before the rename: `nm-settings-nmcli(5)` warns that such a profile can apply to the wrong interface, and one that stops matching is replaced by an auto-generated profile whose new UUID derives a different address again.
- Reinstalling the host, or anything else that regenerates `/var/lib/NetworkManager/secret_key` or `/etc/machine-id`.

Preserve both of those files when restoring a host from backup to keep the generated addresses.

## Read the new addresses

Read the addresses after rebooting, not after `nixos-rebuild switch`.
`usePredictableInterfaceNames` reaches the host as the `net.ifnames=0` kernel parameter, so interfaces keep their old names until the next boot, and an address read before the rename is reseeded by it.
The `.link` pins in `modules/<host>/networking.nix` take effect at that boot too, so a name they create matches no device until then, and anything keyed to it is inert for that window.

Read one address per connection profile that carries a reservation or an ACL entry, not one per host.
Each profile has its own UUID and therefore its own derived address, so a host with several saved Wi-Fi networks presents a different address on each.
Activate the profile, then read what the device presents for it; `nmcli device connect` would activate whichever profile autoconnect picks rather than the one being re-keyed:

```bash
nmcli connection show                       # profile names
nmcli connection up "<profile name>"
nmcli -f GENERAL.HWADDR device show wlan0
```
