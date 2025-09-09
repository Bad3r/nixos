{
  flake.nixosModules.apps.httpie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpie ];
    };
}
