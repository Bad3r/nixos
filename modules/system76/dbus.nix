{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      services.dbus = {
        enable = true;
        packages = lib.mkAfter [ pkgs.dconf ];
      };
    };
}
