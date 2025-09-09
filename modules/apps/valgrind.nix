{
  flake.modules.nixos.apps.valgrind =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.valgrind ];
    };
}
