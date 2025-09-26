{
  flake.nixosModules.apps.flarectl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.flarectl ];
    };
}
