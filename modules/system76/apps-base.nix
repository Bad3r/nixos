/*
  System76 Apps Auto-Import

  This module automatically imports ALL app modules from flake.nixosModules.apps.
  All app modules default to disabled, so only apps explicitly enabled in
  apps-enable.nix will be activated.

  This eliminates the need for manual category management - just:
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
  configurations.nixos.system76.module.imports = getAllApps;
}
