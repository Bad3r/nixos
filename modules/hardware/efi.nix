{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.efivar
        pkgs.efibootmgr
      ];
    };
}
