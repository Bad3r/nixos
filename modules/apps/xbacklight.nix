{
  flake.nixosModules.apps.xbacklight =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xbacklight ];
    };
}
