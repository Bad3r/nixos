{
  flake.nixosModules.apps.lsof =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lsof ];
    };
}
