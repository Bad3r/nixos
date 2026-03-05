{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      services.openssh.settings = {
        X11Forwarding = true;
        X11DisplayOffset = 10;
        X11UseLocalhost = true;
      };

      environment.systemPackages = lib.mkAfter [
        pkgs.xauth
        pkgs.xhost
      ];
    };
}
