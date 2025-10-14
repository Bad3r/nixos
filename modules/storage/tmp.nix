_: {
  flake.nixosModules.roles.system.storage.imports = [
    (_: {
      boot.tmp.cleanOnBoot = true;
    })
  ];
}
