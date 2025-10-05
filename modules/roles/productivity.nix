{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  inputs = config._module.args.inputs or { };
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
    { config, lib, ... }:
    lib.mkIf (config ? environment) {
      environment.systemPackages = lib.mkDefault [
        inputs.nix-logseq-git-flake.packages.${config.system}.logseq
      ];
      services.logseq = {
        enable = lib.mkDefault true;
        timerOnCalendar = lib.mkDefault "02:00";
        package = lib.mkDefault inputs.nix-logseq-git-flake.packages.${config.system}.logseq;
      };
    };
  roleImports = getApps productivityApps ++ [ logseqRoleSettings ];
in
{
  flake.nixosModules.roles.productivity.imports = roleImports;
}
