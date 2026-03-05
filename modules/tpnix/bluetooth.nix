{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      environment.systemPackages = lib.mkAfter [ pkgs.bluetui ];
    };
}
