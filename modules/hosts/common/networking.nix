{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, ... }:
      {
        networking = {
          networkmanager.enable = true;
          useDHCP = lib.mkDefault true;
        };
      }
    )
  ];
}
