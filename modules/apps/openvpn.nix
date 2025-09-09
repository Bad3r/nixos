{
  flake.modules.nixos.apps.openvpn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openvpn ];
    };
}
