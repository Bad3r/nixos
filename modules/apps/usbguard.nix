{
  flake.nixosModules.apps."usbguard" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.usbguard ];
    };
}
