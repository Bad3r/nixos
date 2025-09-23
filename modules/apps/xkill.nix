{
  flake.nixosModules.apps.xkill =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xkill ];
    };
}
