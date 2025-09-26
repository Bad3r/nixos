{
  flake.nixosModules.apps.usbutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.usbutils ];
    };
}
