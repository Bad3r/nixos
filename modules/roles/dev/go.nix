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
      throw ("Unknown NixOS app '" + name + "' (role dev go)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  goModule =
    if lib.hasAttrByPath [ "lang" "go" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "lang" "go" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.lang.go missing while constructing role.dev.go";

  goApps = [
    "go"
    "gopls"
    "golangci-lint"
    "delve"
  ];
  goImports = [ goModule ] ++ getApps goApps;
in
{
  flake.nixosModules.roles.dev.go.imports = goImports;
}
