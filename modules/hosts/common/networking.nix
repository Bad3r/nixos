{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, ... }:
      {
        networking = {
          networkmanager = {
            enable = true;
            # "stable" keeps a per-connection hashed MAC so captive portals and
            # DHCP reservations survive reconnects.
            wifi.macAddress = lib.mkDefault "stable";
            ethernet.macAddress = lib.mkDefault "stable";
          };
          useDHCP = lib.mkDefault true;
        };
      }
    )
  ];
}
