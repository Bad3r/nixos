{ lib, ... }:
{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkDefault [
        pkgs.p7zip
        pkgs.p7zip-rar
      ];
    };
}
