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
      throw ("Unknown NixOS app '" + name + "' (role dev python)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  pythonModule =
    if lib.hasAttrByPath [ "lang" "python" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "lang" "python" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.lang.python missing while constructing role.dev.python";

  pythonApps = [
    "python"
    "uv"
    "ruff"
    "pyright"
  ];
  pythonImports = [ pythonModule ] ++ getApps pythonApps;
in
{
  flake.nixosModules.roles.dev.python.imports = pythonImports;
}
