{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role productivity)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  productivityApps = [
    "electron-mail"
    "logseq"
    "marktext"
    "mattermost"
    "obsidian"
    "pandoc"
    "planify"
    "raindrop"
  ];

  logseqRoleSettings =
    { lib, ... }:
    {
      apps.logseq = {
        ghq.enable = lib.mkDefault true;
        updateTimer.enable = lib.mkDefault true;
        updateTimer.onCalendar = lib.mkDefault "03:30";
      };
    };
  roleImports = getApps productivityApps ++ [ logseqRoleSettings ];
in
{
  flake.nixosModules.roles.productivity.imports = roleImports;
}
