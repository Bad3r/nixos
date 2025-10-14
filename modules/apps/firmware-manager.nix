{
  flake.nixosModules.apps."firmware-manager" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."firmware-manager" ];
    };
}
