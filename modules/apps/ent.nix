{
  flake.nixosModules.apps.ent =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ent ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ent ];
    };
}
