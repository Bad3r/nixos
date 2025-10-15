{ lib, ... }:
let
  bluetoothModule =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        bluetui
      ];
      hardware.bluetooth.enable = true;
    };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "audio-video.media";
      modules = [ bluetoothModule ];
    }
  ];
}
