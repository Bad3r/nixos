{
  flake.nixosModules.apps.s5cmd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.s5cmd ];
    };
}
