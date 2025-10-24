{ config, lib, ... }:
let
  appsDir = ../apps;
  moduleArgs = config._module.args or { };
  inputs = moduleArgs.inputs or { };
  nixosModulesFromSelf = lib.attrByPath [ "outputs" "nixosModules" ] { } (inputs.self or { });
  helpers = moduleArgs.nixosAppHelpers or { };
  fallbackGetApp =
    name:
    let
      filePath = appsDir + "/${name}.nix";
    in
    if builtins.pathExists filePath then
      let
        exported = import filePath;
        module = lib.attrByPath [
          "flake"
          "nixosModules"
          "apps"
          name
        ] null exported;
      in
      if module != null then
        module
      else
        throw ("NixOS app '" + name + "' missing expected attrpath in " + toString filePath)
    else
      throw ("NixOS app module file not found: " + toString filePath);
  getApp = helpers.getApp or fallbackGetApp;
  getApps = helpers.getApps or (names: map getApp names);

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

  vpnDefaultsModule = lib.attrByPath [ "vpn-defaults" ] null nixosModulesFromSelf;
  optionalImports = lib.optional (vpnDefaultsModule != null) vpnDefaultsModule;
in
{
  configurations.nixos.system76.module.imports = getApps netAppNames ++ optionalImports;
}
