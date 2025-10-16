{
  flake.nixosModules.apps."xf86-input-evdev" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xf86inputevdev ];
    };
}
