{ lib, ... }:
let
  sshX11Module =
    { pkgs, ... }:
    {
      # X11 forwarding for GUI systems
      services.openssh.settings = {
        X11Forwarding = true;
        X11DisplayOffset = 10;
        X11UseLocalhost = true;
      };

      # X11 authentication tools required for forwarding
      environment.systemPackages = with pkgs; [
        xorg.xauth
        xorg.xhost
      ];
    };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "network.remote-access";
      modules = [ sshX11Module ];
    }
  ];
}
