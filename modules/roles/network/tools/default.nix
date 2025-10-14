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
      throw ("Unknown NixOS app '" + name + "' (role network.tools)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  toolApps = [
    "circumflex"
    "httpx"
    "httpie"
    "curlie"
    "curl"
    "wget"
    "mitmproxy"
    "dnsleak"
    "socat"
  ];
  roleImports = getApps toolApps;
in
{
  flake.nixosModules.roles.network.tools = {
    metadata = {
      canonicalAppStreamId = "Network";
      categories = [ "Network" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
