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
      throw ("Unknown NixOS app '" + name + "' (role development.ai)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  aiApps = [
    "claude-code"
    "codex"
    "coderabbit-cli"
    "github-mcp-server"
  ];
  aiImports = getApps aiApps;
in
{
  flake.nixosModules.roles.development.ai = {
    metadata = {
      canonicalAppStreamId = "Development";
      categories = [ "Development" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = aiImports;
  };
}
