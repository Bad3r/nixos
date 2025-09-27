{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        bluetui
      ];
      hardware.bluetooth.enable = true;
    };
}
