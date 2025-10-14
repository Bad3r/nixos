{
  flake.nixosModules.apps."bluez" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bluez ];
    };
}
