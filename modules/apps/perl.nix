{
  flake.nixosModules.apps."perl" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."perl" ];
    };
}
