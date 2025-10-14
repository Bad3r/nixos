{ lib, ... }:
{
  flake.nixosModules.roles.system.storage.imports = lib.mkAfter [
    (_: {
      boot.tmp.cleanOnBoot = true;
    })
  ];
}
