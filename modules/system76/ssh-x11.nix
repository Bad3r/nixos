{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      services.openssh.settings = {
        X11Forwarding = true;
        X11DisplayOffset = 10;
        X11UseLocalhost = true;
      };

      environment.systemPackages = lib.mkAfter [
        pkgs.xorg.xauth
        pkgs.xorg.xhost
      ];
    };
}
