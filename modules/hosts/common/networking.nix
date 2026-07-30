{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, ... }:
      {
        networking = {
          networkmanager = {
            enable = true;
            # "stable" hashes connection.stable-id (unset here, so the profile
            # UUID) with the machine identity in /var/lib/NetworkManager/
            # secret_key and /etc/machine-id, not the permanent hardware
            # address. DHCP reservations and MAC ACLs need a re-key at cutover
            # and whenever a profile is re-created or the host is reinstalled.
            # See docs/networking/README.md.
            wifi.macAddress = lib.mkDefault "stable";
            ethernet.macAddress = lib.mkDefault "stable";
          };
          useDHCP = lib.mkDefault true;
          # Kernel-order names (eth0, wlan0) instead of the topology-derived
          # enp0s20f0u1u4 style. Kernel order is not tied to a device, so a name
          # that carries a firewall rule is pinned with a .link Name= instead
          # (modules/system76/networking.nix); modules/hosts/common/firewall.nix
          # asserts that every firewallDnsInterfaces value matches the naming
          # scheme the host boots with, or is pinned. Renaming also reseeds every
          # "stable" MAC above, because NetworkManager hashes the interface name
          # into it.
          usePredictableInterfaceNames = lib.mkDefault false;
        };
      }
    )
  ];
}
