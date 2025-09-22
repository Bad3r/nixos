{
  flake.nixosModules.apps.tealdeer =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tealdeer ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tealdeer ];
    };
}
