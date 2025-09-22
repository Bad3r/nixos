{
  flake.nixosModules.apps.cargo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cargo ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cargo ];
    };
}
