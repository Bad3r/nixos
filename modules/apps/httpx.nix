{
  flake.nixosModules.apps.httpx =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpx ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpx ];
    };
}
