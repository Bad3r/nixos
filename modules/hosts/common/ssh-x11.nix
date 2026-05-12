{ lib, ... }:
let
  body =
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
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
