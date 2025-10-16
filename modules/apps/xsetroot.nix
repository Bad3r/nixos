{
  flake.nixosModules.apps."xsetroot" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xsetroot ];
    };
}
