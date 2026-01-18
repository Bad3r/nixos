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
            package = pkgs.i3;
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
        xfce4-settings
        xfce4-power-manager
        xclip
        xorg.xbacklight
      ];

    };
in
{
  flake.nixosModules."window-manager".i3 = i3SessionModule;
}
