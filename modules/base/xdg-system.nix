_: {
  flake.nixosModules.roles.system.base.imports = [
    (_: {
      xdg.menus.enable = true;
      xdg.mime.enable = true;
    })
  ];
}
