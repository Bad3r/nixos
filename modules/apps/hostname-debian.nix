{
  flake.nixosModules.apps."hostname-debian" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."hostname-debian" ];
    };
}
