_: {
  flake.nixosModules.roles."audio-video".media.imports = [
    (
      { lib, ... }:
      {
        services.pipewire = {
          enable = lib.mkDefault true;
          alsa = {
            enable = lib.mkDefault true;
            support32Bit = lib.mkDefault true;
          };
          pulse.enable = lib.mkDefault true;
        };
        security.rtkit.enable = lib.mkDefault true;
      }
    )
  ];
}
