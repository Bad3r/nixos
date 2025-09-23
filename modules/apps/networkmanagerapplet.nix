{
  flake.nixosModules.apps.networkmanagerapplet =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanagerapplet ];
    };
}
