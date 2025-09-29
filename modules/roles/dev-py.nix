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
      throw ("Unknown NixOS app '" + name + "' (role dev py)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  pythonModule = config.flake.nixosModules.lang.python;

  pythonApps = [
    "python"
    "uv"
    "ruff"
    "pyright"
  ];
  pythonImports = [ pythonModule ] ++ getApps pythonApps;
in
{
  flake.nixosModules.roles.dev.py.imports = pythonImports;
}
