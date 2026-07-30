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
        };
      }
    )
  ];
}
