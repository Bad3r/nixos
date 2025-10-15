{ lib, ... }:
let
  xdgSystemModule = _: {
    xdg.menus.enable = true;
    xdg.mime.enable = true;
  };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.base";
      modules = [ xdgSystemModule ];
    }
  ];
}
