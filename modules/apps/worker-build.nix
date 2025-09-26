{
  flake.nixosModules.apps."worker-build" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."worker-build" ];
    };
}
