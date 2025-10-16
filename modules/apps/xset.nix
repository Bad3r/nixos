{
  flake.nixosModules.apps."xset" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xset ];
    };
}
