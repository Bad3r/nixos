{
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib.meta.owner) username;
  flakeAttrs = config.flake or { };
  nixosModules = flakeAttrs.nixosModules or { };
  roleHelpers = config._module.args.nixosRoleHelpers or { };
  rawResolveRole = roleHelpers.getRole or (_: null);
  resolveRole =
    name:
    let
      candidateEval = builtins.tryEval (rawResolveRole name);
      candidate = if candidateEval.success then candidateEval.value else null;
      namePath = lib.splitString "." name;
      rolePath = [ "roles" ] ++ namePath;
    in
    if candidate != null then
      candidate
    else if lib.hasAttrByPath rolePath nixosModules then
      lib.getAttrFromPath rolePath nixosModules
    else if lib.hasAttrByPath rolePath config.flake.nixosModules then
      lib.getAttrFromPath rolePath config.flake.nixosModules
    else
      throw ("Unknown role '" + name + "' referenced by flake.nixosModules.workstation");
  appHelpers = config._module.args.nixosAppHelpers or { };
  rawAppHelpers = (config.flake.lib.nixos or { }) // appHelpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' referenced by workstation role");
  getApp = rawAppHelpers.getApp or fallbackGetApp;
  getApps = rawAppHelpers.getApps or (names: map getApp names);
  workstationRoles = [
    "xserver"
    "cli"
    "files"
    "dev"
    "media"
    "net"
    "productivity"
    "ai-agents"
    "gaming"
    "security"
    "cloudflare"
  ];
  pythonRoleModules = getApps [
    "python"
    "uv"
    "ruff"
    "pyright"
  ];
  goRoleModules = getApps [
    "go"
    "gopls"
    "golangci-lint"
    "delve"
  ];
  rustRoleModules = getApps [
    "rustc"
    "cargo"
    "rust-analyzer"
    "rustfmt"
    "rust-clippy"
  ];
  cljRoleModules = getApps [
    "clojure-cli"
    "clojure-lsp"
    "leiningen"
    "babashka"
    "pixman"
  ];
  devLanguageModules = pythonRoleModules ++ goRoleModules ++ rustRoleModules ++ cljRoleModules;
  baseImport =
    if rawResolveRole "base" != null then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] nixosModules then
      [ (lib.getAttrFromPath [ "base" ] nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing workstation bundle";
  hmGuiModule =
    let
      hmModules = flakeAttrs.homeManagerModules or { };
    in
    lib.attrByPath [ "gui" ] null hmModules;
in
{
  flake.nixosModules.workstation = {
    imports = baseImport ++ map resolveRole workstationRoles ++ devLanguageModules;
    config = lib.mkIf (hmGuiModule != null) {
      home-manager.users.${username}.imports = [ hmGuiModule ];
    };
  };
}
