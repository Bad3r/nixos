{ config, ... }:
{
  # Networking role: bring in networking apps and VPN defaults precisely
  flake.modules.nixos.roles.net.imports =
    (with config.flake.modules.nixos.apps; [
      httpx
      curlie
      tor
      openvpn
      wireguard-tools
      protonvpn-gui
      ktailctl
      networkmanager-dmenu
    ])
    ++ [ config.flake.modules.nixos.vpn-defaults ];
}
