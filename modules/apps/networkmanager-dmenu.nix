{
  flake.modules.nixos.apps.networkmanager-dmenu =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager_dmenu ];
    };
}
