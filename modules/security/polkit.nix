{
  flake.nixosModules.base = {
    security.polkit.enable = true;
  };
}
