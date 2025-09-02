_: {
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      # Add GSettings desktop schemas for GTK/Electron applications
      environment.systemPackages = with pkgs; [
        gsettings-desktop-schemas
        glib # for gsettings command
      ];

      # Ensure GIO modules are available
      services.udev.packages = with pkgs; [
        gsettings-desktop-schemas
      ];

      # Add schemas to DBus packages for proper registration
      services.dbus.packages = with pkgs; [
        gsettings-desktop-schemas
      ];
    };
}
