{
  flake.nixosModules.apps."xrdb" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xrdb ];
    };
}
