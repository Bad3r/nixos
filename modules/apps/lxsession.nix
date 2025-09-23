{
  flake.nixosModules.apps.lxsession =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lxsession ];
    };
}
