_: {
  flake.nixosModules.workstation = _: {
    services.printing.enable = false;
  };
}
