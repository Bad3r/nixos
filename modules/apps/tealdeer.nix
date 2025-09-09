{
  flake.nixosModules.apps.tealdeer =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tealdeer ];
    };
}
