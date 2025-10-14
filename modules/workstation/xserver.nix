{ lib, ... }:
{
  flake.nixosModules.roles.system.display.x11.imports = lib.mkAfter [
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
