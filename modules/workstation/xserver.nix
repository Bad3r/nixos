_: {
  flake.nixosModules.roles.system.display.x11.imports = [
    (_: {
      services.xserver = {
        enable = true;
        xkb = {
          layout = "us";
          variant = "";
        };
      };
    })
  ];
}
