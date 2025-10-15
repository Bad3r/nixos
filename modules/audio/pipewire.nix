{ lib, ... }:
let
  pipewireModule =
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
    };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "audio-video.media";
      modules = [ pipewireModule ];
    }
  ];
}
