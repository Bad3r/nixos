{
  flake.nixosModules.apps."i3" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.i3 ];
    };
}
