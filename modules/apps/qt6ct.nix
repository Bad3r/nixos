{
  flake.nixosModules.apps."qt6ct" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.qt6Packages.qt6ct ];
    };
}
