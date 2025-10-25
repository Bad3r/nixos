{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      hardware.bluetooth.enable = true;

      environment.systemPackages = lib.mkAfter [ pkgs.bluetui ];
    };
}
