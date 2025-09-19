{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackHasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;
  fallbackGetApp = name: lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;
  fallbackGetApps = names: map fallbackGetApp (lib.filter fallbackHasApp names);
  getApps = rawHelpers.getApps or fallbackGetApps;
  netApps = [
    "httpx"
    "curlie"
    "tor"
    "openvpn"
    "wireguard-tools"
    "protonvpn-gui"
    "ktailctl"
    "networkmanager-dmenu"
  ];
  roleImports =
    getApps netApps
    # Non-app import: shared VPN defaults module lives outside the apps namespace.
    ++ [ config.flake.nixosModules."vpn-defaults" ];
in
{
  flake.nixosModules.roles.net.imports = roleImports;
  flake.nixosModules."role-net".imports = roleImports;
}
