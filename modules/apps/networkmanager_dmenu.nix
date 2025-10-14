{
  flake.nixosModules.apps."networkmanager_dmenu" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager_dmenu ];
    };
}
