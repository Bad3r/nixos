{
  flake.nixosModules.apps."gtk+3" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gtk3 ];
    };
}
