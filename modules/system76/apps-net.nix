{ config, lib, ... }:
let
  moduleArgs = config._module.args or { };
  inputs = moduleArgs.inputs or { };
  nixosModulesFromSelf = lib.attrByPath [ "outputs" "nixosModules" ] { } (inputs.self or { });
  helpers =
    moduleArgs.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

  netAppNames = [
    "circumflex"
    "httpx"
    "httpie"
    "curlie"
    "curl"
    "wget"
    "tor"
    "tor-browser"
    "ungoogled-chromium"
    "openvpn"
    "wireguard-tools"
    "protonvpn-gui"
    "mitmproxy"
    "wireshark"
    "ktailctl"
    "networkmanager-dmenu"
    "networkmanagerapplet"
    "blueberry"
    "networkmanager-openvpn"
  ];

  vpnDefaultsModule = lib.attrByPath [ "vpn-defaults" ] null nixosModulesFromSelf;
  optionalImports = lib.optional (vpnDefaultsModule != null) vpnDefaultsModule;
in
{
  configurations.nixos.system76.module.imports = getApps netAppNames ++ optionalImports;
}
