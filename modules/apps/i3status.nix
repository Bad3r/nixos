{
  flake.nixosModules.apps."i3status" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.i3status ];
    };
}
