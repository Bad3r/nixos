{ lib, ... }:
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.rar ];
    };
}
