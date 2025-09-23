{
  flake.nixosModules.apps.picom =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.picom ];
    };
}
