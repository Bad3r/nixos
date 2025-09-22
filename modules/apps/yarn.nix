{
  flake.nixosModules.apps.yarn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yarn ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yarn ];
    };
}
