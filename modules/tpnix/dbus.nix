{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      services.dbus = {
        enable = true;
        packages = lib.mkAfter [ pkgs.dconf ];
      };
    };
}
