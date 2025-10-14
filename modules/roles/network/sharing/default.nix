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
      throw ("Unknown NixOS app '" + name + "' (role network.sharing)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  sharingApps = [
    "qbittorrent"
    "localsend"
    "rclone"
    "rsync"
    "nicotine"
    "filen-cli"
    "filen-desktop"
    "dropbox"
  ];
  roleImports = getApps sharingApps;
in
{
  flake.nixosModules.roles.network.sharing = {
    metadata = {
      canonicalAppStreamId = "Network";
      categories = [ "Network" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
