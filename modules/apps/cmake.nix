{
  flake.nixosModules.apps.cmake =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cmake ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cmake ];
    };
}
