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
      throw ("Unknown NixOS app '" + name + "' (role dev.nix)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  nixApps = [
    "nix-output-monitor"
    "nvd"
    "nix-tree"
    "nil"
    "niv"
    "nix-prefetch-github"
    "prefetch-yarn-deps"
    "statix"
    "deadnix"
    "nix-diff"
    "nix-index"
    "nix-index-update"
    "cachix"
    "nh"
    "nix-eval-jobs"
    "nix-prefetch-git"
  ];

  roleImports = getApps nixApps;
in
{
  flake.nixosModules.roles.dev.nix.imports = roleImports;
}
