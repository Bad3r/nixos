{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
  names = [
    "httpx"
    "curlie"
    "tor"
    "openvpn"
    "wireguard-tools"
    "protonvpn-gui"
    "ktailctl"
    "networkmanager-dmenu"
  ];
  roleImports = getApps names ++ [ config.flake.nixosModules."vpn-defaults" ];
in
{
  # Networking role: bring in networking apps via robust lookup and include VPN defaults
  flake.nixosModules.roles.net.imports = roleImports;

  # Stable alias for host imports (avoid self-referencing nested aggregator)
  flake.nixosModules."role-net".imports = roleImports;
}
