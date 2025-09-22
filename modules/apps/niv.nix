{
  flake.nixosModules.apps.niv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.niv ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.niv ];
    };
}
