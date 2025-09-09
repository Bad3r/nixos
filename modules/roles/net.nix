{ config, ... }:
{
  # Networking role: bring in networking apps and VPN defaults precisely
  flake.nixosModules.roles.net.imports =
    (with config.flake.nixosModules.apps; [
      httpx
      curlie
      tor
      openvpn
      wireguard-tools
      protonvpn-gui
      ktailctl
      networkmanager-dmenu
    ])
    ++ [ config.flake.nixosModules.vpn-defaults ];
}
