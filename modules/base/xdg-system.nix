{
  flake.nixosModules.workstation = _: {
    xdg.menus.enable = true;
    xdg.mime.enable = true;
  };
}
