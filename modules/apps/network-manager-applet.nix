{
  flake.nixosModules.apps."network-manager-applet" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanagerapplet ];
    };
}
