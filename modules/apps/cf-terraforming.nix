{
  flake.nixosModules.apps."cf-terraforming" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."cf-terraforming" ];
    };
}
