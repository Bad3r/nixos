/*
  Apps Auto-Import (common baseline)

  Imports every app module from flake.nixosModules.apps into the host module
  tree. All app modules default to disabled; only apps explicitly enabled in
  apps-enable.nix activate.

  This module does not read `shareCommon` itself. The host constructor imports
  the aggregate common module only for hosts opted in through the registry;
  reading the registry from this app-import layer would force `flake.lib.nixos`
  while custom overlays are still resolving app options.

  Usage:
    1. Create module in modules/apps/
    2. Enable in apps-enable.nix
*/
{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getAllApps;
in
{
  flake.nixosModules.hosts-common.imports = getAllApps;
}
