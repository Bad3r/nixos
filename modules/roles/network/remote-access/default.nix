{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role network.remote-access)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  remoteApps = [
    "tor"
    "tor-browser"
    "openvpn"
    "wireguard-tools"
    "protonvpn-gui"
    "networkmanager-dmenu"
    "networkmanagerapplet"
    "NetworkManager-openvpn"
    "ktailctl"
  ];

  vpnDefaults = lib.attrByPath [ "vpn-defaults" ] null config.flake.nixosModules;
  roleImports = getApps remoteApps ++ lib.optional (vpnDefaults != null) vpnDefaults;
in
{
  flake.nixosModules.roles.network."remote-access" = {
    metadata = {
      canonicalAppStreamId = "Network";
      categories = [ "Network" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
