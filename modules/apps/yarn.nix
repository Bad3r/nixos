{
  flake.nixosModules.apps.yarn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yarn ];
    };
}
