let
  i3SessionModule =
    { pkgs, lib, ... }:
    {
      # X11 + i3 window manager
      services = {
        xserver = {
          enable = lib.mkDefault true;
          windowManager.i3 = {
            enable = true;
            package = pkgs.i3-gaps;
          };
          displayManager.lightdm.enable = true;
        };

        displayManager.defaultSession = lib.mkDefault "none+i3";

        "systemd-lock-handler".enable = lib.mkDefault true;
      };

      # Provide core tools referenced by the i3 session
      environment.systemPackages = with pkgs; [
        arandr
        dunst
        hsetroot
        i3lock-color
        autotiling-rs
        i3status-rust
        lxsession
        maim
        picom
        rofi
        xfce.xfce4-settings
        xfce.xfce4-power-manager
        xclip
        xorg.xbacklight
      ];

      xdg.mime.defaultApplications = {
        "inode/directory" = lib.mkDefault "nemo.desktop";
        "application/x-directory" = lib.mkDefault "nemo.desktop";
      };
    };
in
{
  flake.nixosModules."window-manager".i3 = i3SessionModule;
}
