{
  flake.nixosModules.pc = _: {
    xdg.menus.enable = true;
    xdg.mime.enable = true;
  };
}
