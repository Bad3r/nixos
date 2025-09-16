{
  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      # X11 + i3 window manager
      services.xserver = {
        enable = lib.mkDefault true;
        displayManager = {
          lightdm.enable = true;
          defaultSession = "none+i3";
        };
        windowManager.i3.enable = true;
      };

      # Useful i3 companions
      environment.systemPackages = with pkgs; [
        i3status
        i3lock
      ];
    };
}
