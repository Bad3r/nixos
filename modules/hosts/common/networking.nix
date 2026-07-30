{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, ... }:
      {
        networking = {
          networkmanager = {
            enable = true;
            # "stable" hashes connection.stable-id with the machine identity in
            # /var/lib/NetworkManager/secret_key (and /etc/machine-id for v2
            # keys), not the permanent hardware address: DHCP reservations and
            # MAC ACLs need a one-time re-key at cutover, and again whenever
            # that identity is regenerated. See docs/networking/README.md.
            wifi.macAddress = lib.mkDefault "stable";
            ethernet.macAddress = lib.mkDefault "stable";
          };
          useDHCP = lib.mkDefault true;
        };
      }
    )
  ];
}
