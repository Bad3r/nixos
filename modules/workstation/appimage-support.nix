{ lib, ... }:
let
  appimageModule = _: {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.base";
      modules = [ appimageModule ];
    }
  ];
}
