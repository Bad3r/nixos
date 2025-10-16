{
  flake.nixosModules.apps."xf86-input-libinput" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xf86inputlibinput ];
    };
}
