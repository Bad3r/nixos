{
  flake.nixosModules.apps.gnused =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnused ];
    };
}
