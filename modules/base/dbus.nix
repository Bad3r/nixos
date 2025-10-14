{ lib, ... }:
{
  flake.nixosModules.roles.system.base.imports = lib.mkAfter [
    (
      { pkgs, ... }:
      {
        services.dbus = {
          enable = true;
          packages = with pkgs; [ dconf ];
        };
      }
    )
  ];
}
