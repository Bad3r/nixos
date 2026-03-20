_: {
  flake.nixosModules.base = {
    services.envfs.enable = true;
  };
}
