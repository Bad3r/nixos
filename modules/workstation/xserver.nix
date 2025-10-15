{ lib, ... }:
let
  xserverModule = _: {
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.display.x11";
      modules = [ xserverModule ];
    }
  ];
}
