{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, ... }:
      {
        networking = {
          networkmanager = {
            enable = true;
            # "stable" keeps a per-connection hashed MAC so captive portals and
            # DHCP reservations survive reconnects. Hosts override at default
            # priority; see modules/tpnix/networking.nix.
            wifi.macAddress = lib.mkDefault "stable";
            ethernet.macAddress = lib.mkDefault "stable";
          };
          useDHCP = lib.mkDefault true;
        };
      }
    )
  ];
}
