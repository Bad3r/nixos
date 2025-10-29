{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      environment.systemPackages = lib.mkAfter [ pkgs.bluetui ];
    };
}
