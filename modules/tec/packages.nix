{ config, ... }:
{
  configurations.nixos.tec.module =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Development tools
        kiro-fhs # Kiro editor with FHS environment
        vscode-fhs # VS Code with FHS environment

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
