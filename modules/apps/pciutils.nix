{
  flake.nixosModules.apps.pciutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pciutils ];
    };
}
