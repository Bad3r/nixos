_: {
  flake.nixosModules.pc = _: {
    services.printing.enable = false;
  };
}
