{ lib, ... }:
let
  tmpModule = _: {
    boot.tmp.cleanOnBoot = true;
  };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.storage";
      modules = [ tmpModule ];
    }
  ];
}
