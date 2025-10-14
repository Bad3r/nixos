{
  flake.nixosModules.apps."xdg-utils" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xdg-utils" ];
    };
}
