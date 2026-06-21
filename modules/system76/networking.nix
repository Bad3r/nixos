_: {
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      networking = {
        networkmanager.enable = true;
        useDHCP = lib.mkDefault true;
      };
    };
}
