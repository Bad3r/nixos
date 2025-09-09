{
  flake.nixosModules.apps.spectacle =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.spectacle ];
    };
}
