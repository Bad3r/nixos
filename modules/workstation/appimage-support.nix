{ lib, ... }:
{
  flake.nixosModules.roles.system.base.imports = lib.mkAfter [
    (_: {
      programs.appimage = {
        enable = true;
        binfmt = true;
      };
    })
  ];
}
