{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (net role)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  netApps = [
    "circumflex"
    "httpx"
    "httpie"
    "curlie"
    "curl"
    "wget"
    "tor"
    "tor-browser"
    "openvpn"
    "wireguard-tools"
    "protonvpn-gui"
    "mitmproxy"
    "ktailctl"
    "networkmanager-dmenu"
    "networkmanagerapplet"
    "networkmanager-openvpn"
    "dnsleak" # TODO: Submit to Nixpkgs repo
  ];
  roleImports =
    getApps netApps
    # Non-app import: shared VPN defaults module lives outside the apps namespace.
    ++ [ config.flake.nixosModules."vpn-defaults" ];
in
{
  flake.nixosModules.roles.net.imports = roleImports;
}
