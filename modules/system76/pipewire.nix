{
  configurations.nixos.system76.module = {
    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    security.rtkit.enable = true;
  };
}
