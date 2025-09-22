{
  flake.nixosModules.apps.kdiskmark =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdiskmark ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdiskmark ];
    };
}
