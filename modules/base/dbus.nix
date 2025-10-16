{ lib, ... }:
let
  dbusModule =
    { pkgs, ... }:
    {
      services.dbus = {
        enable = true;
        packages = with pkgs; [ dconf ];
      };
    };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.base";
      modules = [ dbusModule ];
    }
  ];
}
