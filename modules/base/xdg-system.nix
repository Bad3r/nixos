{ lib, ... }:
{
  flake.nixosModules.roles.system.base.imports = lib.mkAfter [
    (_: {
      xdg.menus.enable = true;
      xdg.mime.enable = true;
    })
  ];
}
