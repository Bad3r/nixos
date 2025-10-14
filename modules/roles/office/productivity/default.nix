{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  inputs = config._module.args.inputs or { };
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role office.productivity)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  logseqRoleSettings =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (config ? environment) {
      environment.systemPackages = lib.mkAfter [
        inputs.nix-logseq-git-flake.packages.${pkgs.system}.logseq
      ];
    };

  productivityApps = [
    "electron-mail"
    "logseq"
    "marktext"
    "mattermost"
    "mattermost-desktop"
    "obsidian"
    "pandoc"
    "pandoc-cli"
    "planify"
    "raindrop"
    "stash"
    "tesseract"
  ];
  roleImports = getApps productivityApps ++ [ logseqRoleSettings ];
in
{
  flake.nixosModules.roles.office.productivity = {
    metadata = {
      canonicalAppStreamId = "Office";
      categories = [ "Office" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
