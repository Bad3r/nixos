{
  flake.nixosModules.apps.httpx =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpx ];
    };
}
