{
  flake.nixosModules.apps.tor =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tor ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tor ];
    };
}
