{
  flake.nixosModules.apps."xinput" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xinput ];
    };
}
