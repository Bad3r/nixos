{
  flake.nixosModules.apps."xfce4-settings" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xfce.xfce4-settings ];
    };
}
