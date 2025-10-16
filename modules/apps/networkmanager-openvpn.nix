{
  flake.nixosModules.apps."NetworkManager-openvpn" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager-openvpn ];
    };
}
