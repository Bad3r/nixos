{ config, lib, ... }:
let
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
  hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;
  getApp = name: lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;
  roleImports = (map getApp (lib.filter hasApp names)) ++ [
    config.flake.nixosModules."vpn-defaults"
  ];
in
{
  # Networking role: bring in networking apps via robust lookup and include VPN defaults
  flake.nixosModules.roles.net.imports = roleImports;

  # Stable alias for host imports (avoid self-referencing nested aggregator)
  flake.nixosModules."role-net".imports = roleImports;
}
