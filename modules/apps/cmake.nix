{
  flake.nixosModules.apps.cmake =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cmake ];
    };
}
