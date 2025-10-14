{
  flake.nixosModules.apps."nodejs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nodejs" ];
    };
}
