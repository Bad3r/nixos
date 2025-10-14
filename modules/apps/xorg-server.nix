{
  flake.nixosModules.apps."xorg-server" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xorgserver ];
    };
}
