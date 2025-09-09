{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        bluetui
      ];
      hardware.bluetooth.enable = true;
    };
}
