{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Application launchers
        rofi
        dmenu

        # Display configuration
        arandr

        # Bluetooth management
        blueberry

        # Wallpaper setter
        hsetroot

        # Screenshot tool
        maim

        # File manager
        nemo

        # NetworkManager GUI utilities
        networkmanager_dmenu
      ];
    };
}
