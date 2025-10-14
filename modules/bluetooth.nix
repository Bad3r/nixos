_: {
  flake.nixosModules.roles."audio-video".media.imports = [
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
