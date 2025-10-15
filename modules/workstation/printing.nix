{ lib, ... }:
let
  printingModule = _: { services.printing.enable = false; };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.base";
      modules = [ printingModule ];
    }
  ];
}
