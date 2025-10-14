{
  flake.nixosModules.apps."setxkbmap" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.setxkbmap ];
    };
}
