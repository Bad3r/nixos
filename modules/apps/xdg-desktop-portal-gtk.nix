{
  flake.nixosModules.apps."xdg-desktop-portal-gtk" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xdg-desktop-portal-gtk" ];
    };
}
