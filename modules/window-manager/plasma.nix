_: {
  flake.modules.nixos.pc =
    { lib, pkgs, ... }:
    {
      # Display manager
      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
      };

      # Plasma 6 desktop
      services.desktopManager.plasma6.enable = true;

      # Set Qt platform theme (kde6 is not yet a valid value, use kde)
      qt.platformTheme = lib.mkForce "kde";

      # Required for some KDE apps
      programs.dconf.enable = true;

      # Enable KDE Connect
      programs.kdeconnect.enable = true;

      # XDG portal for KDE
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
      };

      # Keep packages out of the service wiring; see plasma-defaults.nix and per-app modules
      environment.systemPackages = lib.mkBefore [ ];
    };
}
