{
  flake.nixosModules.apps.okular =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.okular ];
    };
}
