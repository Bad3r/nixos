{
  flake.nixosModules.apps."xfce4-power-manager" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xfce.xfce4-power-manager ];
    };
}
