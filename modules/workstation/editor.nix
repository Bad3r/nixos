{ lib, ... }:
{
  flake.nixosModules.roles.development.core.imports = lib.mkAfter [
    (_: {
      programs.neovim = {
        enable = true;
        vimAlias = true;
        viAlias = true;
        defaultEditor = true;
      };
      programs.nano.enable = false;
    })
  ];
}
