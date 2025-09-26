{
  flake.nixosModules.apps.findutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.findutils ];
    };
}
