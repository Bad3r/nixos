{ config, ... }:
{
  configurations.nixos.tec.module =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Additional system-specific tools
        ktailctl # KDE Tailscale GUI
        localsend # Local network file sharing

        # Additional CLI tools for this system
        httpx
        curlie
        tor
        gpg-tui
        gopass
      ];
    };
}
