{ lib, ... }:
{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.gzip ];
    };
}
