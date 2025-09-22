{
  flake.nixosModules.apps.valgrind =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.valgrind ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.valgrind ];
    };
}
