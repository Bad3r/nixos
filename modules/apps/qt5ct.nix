{
  flake.nixosModules.apps."qt5ct" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.libsForQt5.qt5ct ];
    };
}
