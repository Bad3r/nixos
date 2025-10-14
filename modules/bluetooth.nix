{ lib, ... }:
{
  flake.nixosModules.roles."audio-video".media.imports = lib.mkAfter [
    (
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          bluetui
        ];
        hardware.bluetooth.enable = true;
      }
    )
  ];
}
