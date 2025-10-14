{
  flake.nixosModules.apps."xdg-desktop-portal" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xdg-desktop-portal" ];
    };
}
