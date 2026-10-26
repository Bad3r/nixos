# The `nixos-gui` sbx base, layered on `_base-nixos.nix`: an X11 session
# logged in as `sbx`, with an IceWM desktop and a focused xterm, which root
# and `sbx` reach on DISPLAY :0 from SSH and qemu-ga commands.
{ lib, pkgs, ... }:
{
  services = {
    xserver = {
      enable = true;
      windowManager.icewm.enable = true;
      displayManager.sessionCommands = ''
        ${lib.getExe pkgs.xhost} +SI:localuser:root +SI:localuser:sbx
        ${lib.getExe pkgs.xterm} -fa Monospace -fs 12 &
      '';
    };

    displayManager = {
      defaultSession = "none+icewm";
      autoLogin = {
        enable = true;
        user = "sbx";
      };
    };

    # graphical-desktop.nix defaults for a guest with no sound device or screen reader.
    speechd.enable = false;
    pipewire.enable = false;
  };

  # pam_env sets it for SSH sessions, and the exec launcher sources /etc/profile.
  environment.sessionVariables.DISPLAY = ":0";

  users.users.sbx.isNormalUser = true;

  fonts = {
    enableDefaultPackages = false;
    packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
    ];
  };

  environment.systemPackages = with pkgs; [
    xdotool
    xhost
    xterm
  ];
}
