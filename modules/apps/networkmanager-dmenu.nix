{
  flake.nixosModules.apps.networkmanager-dmenu =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager_dmenu ];
    };
}
