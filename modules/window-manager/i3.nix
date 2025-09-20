{
  flake.nixosModules.pc =
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

        displayManager = {
          # Renamed path for default session
          defaultSession = "none+i3";
        };

        "systemd-lock-handler" = {
          enable = lib.mkDefault true;
        };
      };

      # Provide core tools referenced by the i3 session
      environment.systemPackages = with pkgs; [
        arandr
        dunst
        hsetroot
        i3lock-color
        i3-auto-layout
        i3status-rust
        kitty
        firefox
        lxsession
        maim
        kdePackages.dolphin
        xfce.xfce4-settings
        networkmanagerapplet
        pamixer
        picom
        playerctl
        rofi
        udiskie
        xfce.xfce4-power-manager
        xclip
        xorg.xbacklight
      ];
    };
}
