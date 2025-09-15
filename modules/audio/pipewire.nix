{ lib, ... }:
{
  flake.nixosModules.pc = _: {
    services.pipewire = {
      enable = lib.mkDefault true;
      alsa = {
        enable = lib.mkDefault true;
        support32Bit = lib.mkDefault true;
      };
      pulse.enable = lib.mkDefault true;
    };
    security.rtkit.enable = lib.mkDefault true;

    # PulseAudio is automatically disabled when PipeWire is enabled
  };
}
