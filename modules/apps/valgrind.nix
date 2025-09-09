{
  flake.nixosModules.apps.valgrind =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.valgrind ];
    };
}
