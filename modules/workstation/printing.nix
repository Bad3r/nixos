{ lib, ... }:
{
  flake.nixosModules.roles.system.base.imports = lib.mkAfter [
    (_: { services.printing.enable = false; })
  ];
}
