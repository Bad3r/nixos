{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackHasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;
  fallbackGetApp = name: lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;
  fallbackGetApps = names: map fallbackGetApp (lib.filter fallbackHasApp names);
  getApps = rawHelpers.getApps or fallbackGetApps;
  mediaApps = [
    "mpv"
    "vlc"
    "okular"
    "gwenview"
    "spectacle"
  ];
  roleImports =
    getApps mediaApps
    # Non-app import: include curated media defaults when available.
    ++ lib.optional (config.flake.nixosModules ? media) config.flake.nixosModules.media;
in
{
  flake.nixosModules.roles.media.imports = roleImports;
  flake.nixosModules."role-media".imports = roleImports;
}
