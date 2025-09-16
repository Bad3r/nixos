{
  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      # X11 + i3 window manager
      services.xserver = {
        enable = lib.mkDefault true;
        windowManager.i3.enable = true;
        displayManager.lightdm.enable = true;
      };

      # Renamed path for default session
      services.displayManager.defaultSession = "none+i3";

      # Useful i3 companions
      environment.systemPackages = with pkgs; [
        i3status
        i3lock
      ];
    };
}
