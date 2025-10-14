{
  flake.nixosModules.apps."gtk4" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gtk4 ];
    };
}
