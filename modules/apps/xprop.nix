{
  flake.nixosModules.apps."xprop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xprop" ];
    };
}
