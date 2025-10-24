{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 networking tools.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

  netAppNames = [
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
    "dnsleak"
  ];

  vpnDefaultsModule = lib.attrByPath [ "flake" "nixosModules" "vpn-defaults" ] null config;
  optionalImports = lib.optional (vpnDefaultsModule != null) vpnDefaultsModule;
in
{
  configurations.nixos.system76.module.imports = getApps netAppNames ++ optionalImports;
}
