{
  flake.nixosModules.apps."networkmanager-openvpn" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager-openvpn ];
    };
}
