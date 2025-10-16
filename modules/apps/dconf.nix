{
  flake.nixosModules.apps."dconf" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dconf ];
    };
}
