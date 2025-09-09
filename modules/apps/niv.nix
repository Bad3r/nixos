{
  flake.nixosModules.apps.niv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.niv ];
    };
}
