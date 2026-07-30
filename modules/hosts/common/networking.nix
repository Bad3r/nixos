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
          # enp0s20f0u1u4 style. Hosts with two NICs of one class can see the
          # numbering swap across boots; per-host interface values live in
          # modules/<host>/policy.nix and assume the discovery order recorded
          # there. Renaming also reseeds every "stable" MAC above, because
          # NetworkManager hashes the interface name into it.
          usePredictableInterfaceNames = lib.mkDefault false;
        };
      }
    )
  ];
}
