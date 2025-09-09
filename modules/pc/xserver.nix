{
  flake.nixosModules.pc = {
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
}
