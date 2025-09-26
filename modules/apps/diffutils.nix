{
  flake.nixosModules.apps.diffutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.diffutils ];
    };
}
