{
  flake.nixosModules.apps.openvpn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openvpn ];
    };
}
