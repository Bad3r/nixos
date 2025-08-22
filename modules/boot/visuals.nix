{
  flake.modules.nixos = {
    base = {
      # Boot without splash screen - show all boot messages
      boot.kernelParams = [
        # "quiet" # Disabled - show kernel messages during boot
        # "systemd.show_status=error" # Disabled - show systemd status
      ];
    };
    pc = {
      # Plymouth splash screen disabled
      boot.plymouth.enable = false;
    };
  };
}
