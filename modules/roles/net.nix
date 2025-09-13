{ config, lib, ... }:
{
  # Networking role: bring in networking apps via robust lookup and include VPN defaults
  flake.nixosModules.roles.net.imports =
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
      apps = map getApp (lib.filter hasApp names);
    in
    apps ++ [ config.flake.nixosModules."vpn-defaults" ];

  # Stable alias for host imports
  flake.nixosModules."role-net".imports = config.flake.nixosModules.roles.net.imports;
}
