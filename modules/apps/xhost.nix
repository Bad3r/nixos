{
  flake.nixosModules.apps."xhost" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xhost" ];
    };
}
