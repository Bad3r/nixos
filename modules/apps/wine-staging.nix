{
  flake.nixosModules.apps."wine-staging" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."wine-staging" ];
    };
}
